use std::fs;

use doji::{Engine, Value};

macro_rules! test_e2e {
    ($name:ident, $path:expr, $expected:expr) => {
        #[test]
        fn $name() {
            let path = format!("tests/e2e/programs/{}.doji", $path);
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

// Literals
test_e2e!(literal_nil, "literal_nil", |_| Value::nil());
test_e2e!(literal_bool, "literal_bool", |_| Value::bool(true));
test_e2e!(literal_int, "literal_int", |_| Value::int(42));
test_e2e!(literal_float, "literal_float", |_| Value::float(3.14159));
test_e2e!(literal_string, "literal_string", |heap| Value::string_in(
    heap,
    "boo".to_string()
));

// Features
test_e2e!(feature_closure, "feature_closure", |_| Value::int(7));
test_e2e!(feature_pattern_matching, "feature_pattern_matching", |_| {
    Value::int(10)
});
test_e2e!(
    feature_early_return,
    "feature_early_return",
    |_| Value::int(4)
);
test_e2e!(feature_mutual_recursion, "feature_mutual_recursion", |_| {
    Value::bool(true)
});
test_e2e!(
    feature_last_statement_if,
    "feature_last_statement_if",
    |_| Value::nil()
);
test_e2e!(feature_if_else_if_else, "feature_if_else_if_else", |_| {
    Value::int(45)
});

// Demo programs
test_e2e!(demo_add, "demo_add", |_| Value::float(89.4));
test_e2e!(demo_factorial, "demo_factorial", |_| Value::int(6));
test_e2e!(demo_fibonacci, "demo_fibonacci", |_| Value::int(8));
