import Darwin
import Foundation

@main
@MainActor
struct AntigravityCLITests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "agy")
        let script = #"""
            #!/usr/bin/python3
            import json, sys, time, os
            args = sys.argv[1:]
            if args == ['--version']:
                print('1.5.3'); sys.exit(0)
            if args == ['models']:
                print('test-model\tTest Model'); sys.exit(0)
            assert args[args.index('--input-format')+1] == 'stream-json'
            assert args[args.index('--output-format')+1] == 'stream-json'
            assert json.loads(args[args.index('--settings')+1])['toolPermission'] == 'strict'
            assert '--disable-slash-commands' in args
            message = json.loads(sys.stdin.readline())
            assert message['event'] == 'user'
            text = message['message']['content']
            assert 'earlier marker' in text and 'latest marker' in text
            model = args[args.index('--model')+1]
            if model == 'error':
                print(json.dumps({'event':'result','result':{'status':'ERROR','error':'eligibility blocked'}}))
                sys.exit(1)
            if model == 'wait':
                open('wait.pid', 'w').write(str(os.getpid()))
                step = {'step_type':'agent_response','text_delta':'started'}
                print(json.dumps({'event':'step_update','step_update':step}), flush=True)
                time.sleep(60)
                sys.exit(0)
            if model != 'fallback':
                for text in ['Hello ', 'world']:
                    step = {'step_type':'agent_response','text_delta':text}
                    print(json.dumps({'event':'step_update','step_update':step}), flush=True)
            print(json.dumps({'event':'result','result':{'status':'SUCCESS','response':'Hello world'}}), flush=True)
            """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let launch = InstalledAILaunch(commandPath: executable.path)
        let manager = InstalledAIManager(supportDirectory: root)
        manager.launchSettings = { _ in launch }
        await manager.refresh(kind: .antigravity).value
        precondition(manager.status(for: .antigravity).isReady)
        precondition(manager.models(for: .antigravity).map(\.id) == ["test-model"])
        let request = AIRequest(messages: [
            AIMessage(role: .user, text: "earlier marker"),
            AIMessage(role: .assistant, text: "previous response"),
            AIMessage(role: .user, text: "latest marker")
        ])
        for model in ["test-model", "fallback"] {
            let provider = try manager.provider(kind: .antigravity, model: model, effort: nil)
            var text = ""
            var finished = false
            for try await event in provider.stream(request) {
                if case .text(let part) = event { text += part }
                if case .finished = event { finished = true }
            }
            precondition(text == "Hello world" && finished, "stream must not duplicate its final snapshot")
        }
        let failing = try manager.provider(kind: .antigravity, model: "error", effort: nil)
        do {
            for try await _ in failing.stream(request) {}
            preconditionFailure("a CLI eligibility error must throw")
        } catch {
            precondition(error.localizedDescription.contains("eligibility blocked"))
        }
        let waiting = try manager.provider(kind: .antigravity, model: "wait", effort: nil)
        var started = false
        let task = Task {
            for try await event in waiting.stream(request) {
                if case .text = event { started = true }
            }
        }
        for _ in 0..<100 where !started { try await Task.sleep(for: .milliseconds(50)) }
        precondition(started, "cancellation test must reach the running child")
        let pidFile = root.appending(path: "InstalledAI/Workspace/wait.pid")
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        task.cancel()
        _ = await task.result
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(50)) }
        precondition(kill(pid, 0) != 0, "cancelling must stop the CLI")
        manager.stop()
        print("Antigravity discovery, launch flags, history, stream, fallback and errors passed")
    }
}
