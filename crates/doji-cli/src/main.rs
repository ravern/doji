use doji::{DefaultDriver, DefaultResolver, Engine};

fn main() {
    let mut engine = Engine::<DefaultResolver, DefaultDriver>::builder().build();

    match engine.evaluate_inline::<i64>("3 + 4") {
        Ok(result) => println!("3 + 4 = {}", result),
        Err(error) => eprintln!("error: {}", error),
    }
}
