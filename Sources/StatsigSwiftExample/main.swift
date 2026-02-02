import Statsig

do {
    let user = StatsigUser(userID: "demo-user")
    try Statsig.initialize(sdkKey: "add-your-statsig-server-key-here")
    let gateValue = try Statsig.checkGate(user: user, gate: "gate_name")
    print("gate value: \(gateValue)")
} catch {
    print("Statsig error: \(error)")
}
