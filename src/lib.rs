/// WebAssembly component wrapper for hello-rs
///
/// This component exposes the hello-rs library through the WebAssembly Component Model,
/// making it callable from JavaScript in browsers.

mod bindings {
    //! Generated bindings for the greeter world defined in wit/world.wit
    wit_bindgen::generate!({
        path: "wit/world.wit",
    });
}

/// The GreeterComponent struct implements the greeter interface
struct GreeterComponent;

impl bindings::exports::example::greeter::greeter::Guest for GreeterComponent {
    /// Generate a formatted greeting for the given name
    ///
    /// This calls the hello-rs library and then formats the output
    /// by capitalizing each word and adding an exclamation mark.
    ///
    /// Example: "matt" -> "Hello Matt!"
    fn hello(name: String) -> String {
        // Get the base greeting from hello-rs
        let greeting = hello_rs::hello(&name);

        // Format the greeting: capitalize each word and add "!"
        let formatted = greeting
            .split_whitespace()
            .map(|word| {
                let mut chars = word.chars();
                match chars.next() {
                    None => String::new(),
                    Some(first) => {
                        first.to_uppercase().collect::<String>() + chars.as_str()
                    }
                }
            })
            .collect::<Vec<_>>()
            .join(" ");

        format!("{}!", formatted)
    }
}

// Export the component using the generated macro
bindings::export!(GreeterComponent with_types_in bindings);
