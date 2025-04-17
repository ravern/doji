use doji::Engine;

fn main() {
    let engine = Engine::new();
    match engine.run("3 + 4").and_then(i64::try_from) {
        Ok(result) => println!("3 + 4 = {}", result),
        Err(error) => eprintln!("error: {}", error),
    }
}
