import Foundation

@main
struct AgentStateHarness {
    static func main() {
        var machine = AgentPipelineStateMachine()
        guard machine.start(.architect), machine.activeStage == .architect else { fatalError("Architect should start") }
        guard !machine.start(.builder) else { fatalError("Builder cannot overlap Architect") }
        guard machine.pass(.architect), machine.start(.builder), machine.pass(.builder) else { fatalError("Builder transition failed") }
        guard machine.start(.verifier), machine.pass(.verifier), machine.start(.reviewer), machine.pass(.reviewer), machine.canComplete else { fatalError("Verifier/Reviewer transition failed") }
        var failed = AgentPipelineStateMachine()
        _ = failed.start(.architect)
        _ = failed.fail(.architect)
        guard failed.snapshot.states[.builder] == .skipped,
              failed.snapshot.states[.verifier] == .skipped,
              failed.snapshot.states[.reviewer] == .skipped else { fatalError("downstream stages must be skipped") }
        print("pipeline=PASS single-active=PASS downstream-skip=PASS")
    }
}
