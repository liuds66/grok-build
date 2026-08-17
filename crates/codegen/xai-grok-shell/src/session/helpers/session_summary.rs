//! Session title generation via a text-only LLM request.

use crate::sampling::{
    Client as OaiCompatClient, ConversationItem, ConversationRequest, ConversationResponse,
};
use crate::session::helpers::chat::floor_char_boundary;

/// Upper bound on the user text that feeds title generation; titles only need
/// the opening, and this keeps the request well under the model prompt limit.
const TITLE_SOURCE_MAX_BYTES: usize = 8_000;

#[derive(serde::Deserialize)]
struct SessionTitle {
    session_title: String,
}

/// Remove `<system-reminder>…</system-reminder>` blocks from `text` — they are
/// system-injected context (e.g. the `/goal` setup reminder), not the user's
/// words, so they must not drive the session title.
fn strip_system_reminder_blocks(text: &str) -> String {
    const OPEN: &str = "<system-reminder>";
    const CLOSE: &str = "</system-reminder>";
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find(OPEN) {
        out.push_str(&rest[..start]);
        let after_open = &rest[start + OPEN.len()..];
        // An unterminated reminder drops the remainder — it is system text.
        let Some(end) = after_open.find(CLOSE) else {
            return out.trim().to_string();
        };
        rest = &after_open[end + CLOSE.len()..];
    }
    out.push_str(rest);
    out.trim().to_string()
}

/// Text the session title is derived from: strip system reminders and skill XML
/// markup, then cap to the first few KB. Stripping runs before the cap so a
/// leading reminder larger than the cap is still removed.
fn title_source_text(user_message: &str) -> String {
    let without_reminders = strip_system_reminder_blocks(user_message);
    let base = if without_reminders.is_empty() {
        user_message
    } else {
        &without_reminders
    };
    let mut display =
        xai_grok_tools::implementations::skills::skill::extract_skill_display_text(base)
            .unwrap_or_else(|| base.to_string());
    display.truncate(floor_char_boundary(&display, TITLE_SOURCE_MAX_BYTES));
    display
}

pub(crate) fn title_fallback_from_user_text(user_message: &str) -> String {
    let text = title_source_text(user_message);
    let s = text
        .split_whitespace()
        .take(10)
        .collect::<Vec<_>>()
        .join(" ");
    if s.is_empty() {
        "New session".to_string()
    } else {
        s
    }
}

/// Normalize a model-generated title. The preferred response is plain text,
/// but accepting the old JSON shape keeps this compatible with providers that
/// still follow the previous structured-output prompt.
fn title_from_response(response: &ConversationResponse) -> Option<String> {
    let raw = response.assistant_text();
    let text = raw.trim();
    if text.is_empty() {
        return None;
    }

    let candidate = serde_json::from_str::<SessionTitle>(text)
        .ok()
        .map(|parsed| parsed.session_title)
        .filter(|title| !title.trim().is_empty())
        .unwrap_or_else(|| text.to_owned());

    let cleaned = candidate
        .trim()
        .trim_matches('`')
        .trim_matches('"')
        .trim_matches('\'')
        .lines()
        .next()
        .unwrap_or_default()
        .trim();
    (!cleaned.is_empty()).then(|| cleaned.to_owned())
}

/// Generates a title for the session by looking at the first user message.
///
/// This is intentionally a text-only request. Session naming does not need
/// tools, and sending a function tool plus `tool_choice` makes otherwise
/// compatible OpenAI-style providers (notably DeepSeek) reject the request.
fn build_title_request(clean_message: &str, model: &str) -> ConversationRequest {
    ConversationRequest::from_items(vec![
        ConversationItem::system(
            r#"You are tasked with generating the session title. The user is asking almost always software engineering related questions on their codebase.
We describe the session title below
# Session Title
A short and distinctive 5-10 word descriptive title for the session. Super info dense, no filler.

You will be given the user query below encapsulated in <user_query></user_query>.

Return only the title as plain text. Do not call tools. Do not return JSON or markdown."#,
        ),
        ConversationItem::user(format!(
            r#"<user_query>
{}
</user_query>"#,
            clean_message
        )),
    ])
    .with_model(model)
    .with_max_output_tokens(100)
    .with_temperature(1.0)
}

pub async fn generate_session_summary(
    user_message: String,
    client: OaiCompatClient,
    model: &str,
) -> String {
    let clean_message = title_source_text(&user_message);
    let request = build_title_request(&clean_message, model);

    match client.conversation_collect(request).await {
        Ok(response) => {
            if let Some(title) = title_from_response(&response) {
                return title;
            }
            tracing::debug!(model = %model, "session title generation: response was empty");
        }
        Err(e) => {
            tracing::warn!(
                model = %model,
                error = %e,
                "session title generation failed, falling back to truncated user text"
            );
        }
    }
    title_fallback_from_user_text(&clean_message)
}

#[cfg(test)]
mod tests {
    use super::{
        TITLE_SOURCE_MAX_BYTES, strip_system_reminder_blocks, title_fallback_from_user_text,
        build_title_request, title_from_response, title_source_text,
    };
    use crate::sampling::{ConversationItem, ConversationResponse};

    #[test]
    fn title_source_text_caps_oversized_input() {
        let big = "word ".repeat(10_000);
        let out = title_source_text(&big);
        assert!(!out.is_empty() && out.len() <= TITLE_SOURCE_MAX_BYTES);
    }

    #[test]
    fn title_source_text_cap_is_utf8_safe() {
        // 3-byte chars straddle the byte cap; must truncate on a boundary, not panic.
        let big = "あ".repeat(10_000);
        let out = title_source_text(&big);
        assert!(!out.is_empty() && out.len() <= TITLE_SOURCE_MAX_BYTES);
    }

    #[test]
    fn title_source_text_strips_leading_reminder_larger_than_cap() {
        // A leading reminder bigger than the cap must still be stripped, so the
        // title derives from the objective rather than reminder text.
        let reminder = "x".repeat(TITLE_SOURCE_MAX_BYTES * 2);
        let input =
            format!("<system-reminder>\n{reminder}\n</system-reminder>\n\nbuild a mario game");
        let out = title_source_text(&input);
        assert_eq!(out, "build a mario game");
    }

    #[test]
    fn strip_removes_goal_setup_reminder_leaving_objective() {
        let input = "<system-reminder>\nA goal has been set: do stuff\nlots of rules\nStart \
                     now.\n</system-reminder>\n\nbuild a mario platformer game";
        assert_eq!(
            strip_system_reminder_blocks(input),
            "build a mario platformer game"
        );
    }

    #[test]
    fn strip_handles_unterminated_reminder() {
        assert_eq!(
            strip_system_reminder_blocks("<system-reminder>\nrules with no close tag"),
            ""
        );
    }

    #[test]
    fn strip_no_reminder_is_identity() {
        assert_eq!(
            strip_system_reminder_blocks("fix the auth bug"),
            "fix the auth bug"
        );
    }

    /// Regression: a `/goal <objective>` first turn must title off the
    /// objective, not the injected `<system-reminder>` setup block.
    #[test]
    fn fallback_titles_off_goal_objective_not_reminder() {
        let input = "<system-reminder>\nA goal has been set: do stuff\nStart \
                     now.\n</system-reminder>\n\nbuild a mario platformer game in html";
        assert_eq!(
            title_fallback_from_user_text(input),
            "build a mario platformer game in html"
        );
    }

    #[test]
    fn fallback_trims_to_words() {
        assert_eq!(
            title_fallback_from_user_text(
                "one two three four five six seven eight nine ten eleven"
            ),
            "one two three four five six seven eight nine ten"
        );
    }

    #[test]
    fn fallback_new_session_when_whitespace_only() {
        assert_eq!(title_fallback_from_user_text("   \n\t"), "New session");
    }

    #[test]
    fn fallback_strips_skill_xml_with_args() {
        let input = "<command-name>implement</command-name>\n\
                      <command-message>/implement</command-message>\n\
                      <command-args>fix the rendering bug</command-args>";
        assert_eq!(
            title_fallback_from_user_text(input),
            "/implement fix the rendering bug",
        );
    }

    #[test]
    fn fallback_strips_skill_xml_no_args() {
        let input = "<command-name>deploy</command-name>\n\
                      <command-message>/deploy</command-message>";
        assert_eq!(title_fallback_from_user_text(input), "/deploy");
    }

    #[test]
    fn fallback_plain_text_unaffected() {
        assert_eq!(
            title_fallback_from_user_text("fix the auth bug in login.rs"),
            "fix the auth bug in login.rs",
        );
    }

    #[test]
    fn title_response_is_plain_text_without_tools() {
        let response = ConversationResponse {
            items: vec![ConversationItem::assistant("深林 UI 视觉精修")],
            stop_reason: None,
            usage: None,
            cost_usd_ticks: None,
            message_chunks_emitted: 1,
            doom_loop_signals: Vec::new(),
            stop_message: None,
        };
        assert_eq!(title_from_response(&response).as_deref(), Some("深林 UI 视觉精修"));
        assert!(response.assistant().is_some_and(|assistant| assistant.tool_calls.is_empty()));
    }

    #[test]
    fn deepseek_title_request_has_no_tools_or_tool_choice() {
        let request = build_title_request("修复 Rust 构建", "deepseek-v4-flash");
        assert_eq!(request.model.as_deref(), Some("deepseek-v4-flash"));
        assert!(request.tools.is_empty());
        assert!(request.hosted_tools.is_empty());
        assert!(request.tool_choice.is_none());
    }

    #[test]
    fn title_response_accepts_legacy_json_without_requiring_tool_call() {
        let response = ConversationResponse {
            items: vec![ConversationItem::assistant(
                r#"{"session_title":"Rust 核心优化"}"#,
            )],
            stop_reason: None,
            usage: None,
            cost_usd_ticks: None,
            message_chunks_emitted: 1,
            doom_loop_signals: Vec::new(),
            stop_message: None,
        };
        assert_eq!(title_from_response(&response).as_deref(), Some("Rust 核心优化"));
    }
}
