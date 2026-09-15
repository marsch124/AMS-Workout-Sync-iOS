// swift-tools-version:5.9
//
// The part of AMS Workout Sync that reads a training plan, kept apart from the
// app so it can be run on the Mac against real workbooks and compared, row by
// row, with what the web app reads out of the same file. That comparison is the
// whole point of the split: a native app is only safe to trust with his plan
// once it demonstrably understands the plan the way the web app already does.
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutCore", targets: ["WorkoutCore"]),
        .executable(name: "plan-dump", targets: ["PlanDump"]),
        .executable(name: "write-dump", targets: ["WriteDump"]),
        .executable(name: "sync-check", targets: ["SyncCheck"]),
        .executable(name: "form-check", targets: ["FormCheck"])
    ],
    targets: [
        .target(name: "WorkoutCore"),
        .executableTarget(name: "PlanDump", dependencies: ["WorkoutCore"]),
        .executableTarget(name: "WriteDump", dependencies: ["WorkoutCore"]),
        .executableTarget(name: "SyncCheck", dependencies: ["WorkoutCore"]),
        .executableTarget(name: "FormCheck", dependencies: ["WorkoutCore"])
    ]
)
