use std::fs;

use doji::{Engine, Value};

macro_rules! test_e2e {
    ($name:ident, $path:expr, $expected:expr) => {
        #[test]
        fn $name() {
            let path = format!("tests/e2e/{}.doji", $path);
            let source = fs::read_to_string(&path).expect("failed to read source file");
            let mut engine = Engine::new();
            smol::block_on(async {
                let result_value = engine
                    .execute_str(&path, &source)
                    .await
                    .expect("failed to execute program");
                assert_eq!(result_value, $expected(engine.heap()));
            });
        }
    };
}

test_e2e!(int, "int", |_| Value::int(42));
test_e2e!(float, "float", |_| Value::float(3.14159));
test_e2e!(bool, "bool", |_| Value::bool(true));
test_e2e!(string, "string", |heap| Value::string_in(
    heap,
    "boo".to_string()
));
test_e2e!(closure, "closure", |_| Value::int(7));
test_e2e!(let_pattern, "let_pattern", |_| Value::int(10));
test_e2e!(recursion, "recursion", |_| Value::int(6));
test_e2e!(early_return, "early_return", |_| Value::int(4));
test_e2e!(mutual_recursion, "mutual_recursion", |_| Value::bool(true));
test_e2e!(
    if_as_last_statement,
    "if_as_last_statement",
    |_| Value::nil()
);
test_e2e!(if_else, "if_else", |_| Value::int(45));
test_e2e!(add, "add", |_| Value::float(89.4));
test_e2e!(fibonacci, "fibonacci", |_| Value::int(8));
