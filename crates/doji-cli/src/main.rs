use doji::{Engine, Source};

fn main() {
    let mut engine = Engine::new();

    // engine.register("__debug__print", debug_print);

    // engine.resolve("std", "/var/lib/doji/std");

    match engine.evaluate::<i64>(Source::Inline("3 + 4")) {
        Ok(result) => println!("3 + 4 = {}", result),
        Err(error) => eprintln!("error: {}", error),
    }
}

// fn debug_print<'gc>(cx: Context<'gc>) -> Result<Step<'gc>, Error> {
//     let value = cx.pop();
//     println!("{}", value);
//     Ok(Step::Yield(Operation::DebugPrint(value)))
// }
