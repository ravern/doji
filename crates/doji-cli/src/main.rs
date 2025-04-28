use doji::{Engine, RootValue};

fn main() {
    let mut engine = Engine::builder().build();

    match engine.evaluate_inline::<i64>("3 + 4") {
        Ok(answer) => println!("3 + 4 = {}", answer),
        Err(error) => eprintln!("error: {}", error),
    }

    match engine.evaluate_file::<RootValue>("test.doji") {
        Ok(answer) => {
            match engine.unroot::<i64>(answer) {
                Ok(answer) => println!("test.doji = {}", answer),
                Err(error) => {
                    eprintln!("error: {}", error);
                    return;
                }
            };
        }
        Err(error) => eprintln!("error: {}", error),
    }
}
