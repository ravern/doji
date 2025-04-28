use doji::Engine;

fn main() {
    let engine = Engine::builder().build();

    match engine.evaluate_inline::<i64>("3 + 4") {
        Ok(answer) => println!("3 + 4 = {}", answer),
        Err(error) => eprintln!("error: {}", error),
    }
}
