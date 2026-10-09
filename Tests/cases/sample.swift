import SwiftUI

/// A greeting view.
struct Greeting: View {
    @State private var name = "World"

    var body: some View {
        Text("Hello, \(name)!")
            .padding(12)
    }
}

func double(_ x: Int) -> Int { x * 2 }
