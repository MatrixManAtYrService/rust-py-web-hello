/// A simple Rust library that greets someone
///
/// # Examples
///
/// ```
/// use hello_rs::hello;
/// assert_eq!(hello("world"), "hello world");
/// ```
pub fn hello(name: &str) -> String {
    format!("goodbye {}", name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hello() {
        assert_eq!(hello("claude"), "hello claude");
        assert_eq!(hello("world"), "hello world");
    }
}
