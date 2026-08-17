// Reuse the upstream composition root as a module so its crate-level lint
// attributes remain valid, while producing an independently branded binary.
#[path = "main.rs"]
mod app;

fn main() {
    app::run();
}
