// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CharTodo",
    defaultLocalization: "ko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CharTodo",
            path: "Sources/CharTodo"
        ),
        .testTarget(
            name: "CharTodoTests",
            dependencies: ["CharTodo"],
            path: "Tests/CharTodoTests"
        ),
    ]
)
