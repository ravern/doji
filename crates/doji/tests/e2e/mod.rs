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
                assert_eq!(result_value, $expected);
            });
        }
    };
}

test_e2e!(int, "int", Value::int(42));
test_e2e!(float, "float", Value::float(3.14159));
test_e2e!(bool, "bool", Value::bool(true));
test_e2e!(closure, "closure", Value::int(7));
test_e2e!(add, "add", Value::float(89.4));
test_e2e!(fibonacci, "fibonacci", Value::int(8));
