use doji::Engine;

fn main() {
    let engine = Engine::new();
    match engine.run::<i64>("3 + 4") {
        Ok(result) => println!("3 + 4 = {}", result),
        Err(error) => eprintln!("error: {}", error),
    }
}
