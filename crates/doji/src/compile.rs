use std::{cell::RefCell, collections::HashMap, rc::Rc};

use crate::{
    ast::{
        AccessExpression, BinaryExpression, BinaryOperator, Block, CallExpression, Expression,
        FnExpression, Identifier, LetStatement, ListExpression, Literal, MapExpression,
        MapExpressionKey, MapExpressionPair, MemberExpression, Module, Pattern, Statement,
        UnaryExpression, UnaryOperator,
    },
    bytecode::{
        Arity, Chunk, Instruction, InstructionOffset, IntImmediate, StackSlot, Upvalue,
        UpvalueIndex,
    },
    env::Environment,
    error::Error,
    gc::Heap,
    parse::Parser,
    value::{Function, Value},
};

pub struct Compiler {}

impl Compiler {
    pub fn compile<'gc>(
        &mut self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        source: &str,
    ) -> Result<Function, Error> {
        let module = Parser {}.parse(source).unwrap();
        dbg!(Generator {}.generate_module(env, heap, module))
    }
}

struct Generator {}

impl Generator {
    fn generate_module<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        module: Module,
    ) -> Result<Function, Error> {
        let builder = ChunkBuilderHandle::new(0.into());
        self.generate_block(env, heap, &builder, module.block)?;
        builder.push_instructions([
            Instruction::Store(StackSlot::from(0)),
            Instruction::Pop,
            Instruction::Return,
        ]);
        Ok(Function::new(builder.build()))
    }

    fn generate_block<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        block: Block,
    ) -> Result<(), Error> {
        builder.push_scope();
        builder.add_fresh_local("block_return".to_string());
        builder.push_instructions([Instruction::Nil]);
        for statement in block.statements {
            self.generate_statement(env, heap, builder, statement)?;
        }
        if let Some(expression) = block.return_expression {
            self.generate_expression(env, heap, builder, *expression)?;
        } else {
            builder.push_instructions([Instruction::Nil]);
        }
        let scope = builder.pop_scope();
        builder.push_instructions([Instruction::Store(StackSlot::from(scope.base))]);
        // TODO: Handle closing of upvalues.
        for _ in 0..scope.locals.len() {
            builder.push_instructions([Instruction::Pop]);
        }
        Ok(())
    }

    fn generate_statement<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        statement: Statement,
    ) -> Result<(), Error> {
        match statement {
            Statement::Let(let_statement) => {
                self.generate_let_statement(env, heap, builder, let_statement)
            }
            // Statement::For(for_statement) => {
            //     self.generate_for_statement(env, builder, for_statement)
            // }
            // Statement::While(while_statement) => {
            //     self.generate_while_statement(env, builder, while_statement)
            // }
            // Statement::Return(return_statement) => {
            //     self.generate_return_statement(env, builder, return_statement)
            // }
            // Statement::Break(span) => {
            //     builder
            //         .0
            //         .borrow_mut()
            //         .push_code([Instruction::Jump(CodeOffset::from(0))]);
            //     Ok(())
            // }
            // Statement::Continue(span) => {
            //     builder
            //         .0
            //         .borrow_mut()
            //         .push_code([Instruction::Jump(CodeOffset::from(0))]);
            //     Ok(())
            // }
            Statement::Expression(expression) => {
                self.generate_expression(env, heap, builder, expression)?;
                builder.push_instructions([Instruction::Pop]);
                Ok(())
            }
            _ => unimplemented!(),
        }
    }

    fn generate_let_statement<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        let_statement: LetStatement,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *let_statement.value)?;
        self.generate_pattern(env, heap, builder, *let_statement.pattern)
    }

    fn generate_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        expression: Expression,
    ) -> Result<(), Error> {
        match expression {
            Expression::Binary(binary_expression) => {
                self.generate_binary_expression(env, heap, builder, binary_expression)
            }
            Expression::Unary(unary_expression) => {
                self.generate_unary_expression(env, heap, builder, unary_expression)
            }
            Expression::Call(call_expression) => {
                self.generate_call_expression(env, heap, builder, call_expression)
            }
            Expression::Member(member_expression) => {
                self.generate_member_expression(env, heap, builder, member_expression)
            }
            Expression::Access(access_expression) => {
                self.generate_access_expression(env, heap, builder, access_expression)
            }
            // Expression::If(if_expression) => {
            //     self.generate_if_expression(env, builder, if_expression)
            // }
            Expression::Fn(fn_expression) => {
                self.generate_fn_expression(env, heap, builder, fn_expression)
            }
            Expression::Map(map_expression) => {
                self.generate_map_expression(env, heap, builder, map_expression)
            }
            Expression::List(list_expression) => {
                self.generate_list_expression(env, heap, builder, list_expression)
            }
            Expression::Block(block) => self.generate_block(env, heap, builder, block),
            Expression::Identifier(identifier) => {
                self.generate_identifier(env, heap, builder, identifier)
            }
            Expression::Literal(literal) => self.generate_literal(env, heap, builder, literal),
            _ => unimplemented!(),
        }
    }

    fn generate_binary_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        binary_expression: BinaryExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *binary_expression.left)?;
        self.generate_expression(env, heap, builder, *binary_expression.right)?;
        let operator_instruction = match binary_expression.operator {
            BinaryOperator::Add => Instruction::Add,
            BinaryOperator::Sub => Instruction::Sub,
            BinaryOperator::Mul => Instruction::Mul,
            BinaryOperator::Div => Instruction::Div,
            BinaryOperator::Rem => Instruction::Rem,
            BinaryOperator::Eq => Instruction::Eq,
            BinaryOperator::Neq => Instruction::Neq,
            BinaryOperator::Gt => Instruction::Gt,
            BinaryOperator::Gte => Instruction::Gte,
            BinaryOperator::Lt => Instruction::Lt,
            BinaryOperator::Lte => Instruction::Lte,
            BinaryOperator::And => Instruction::And,
            BinaryOperator::Or => Instruction::Or,
            BinaryOperator::BitAnd => Instruction::BitAnd,
            BinaryOperator::BitOr => Instruction::BitOr,
            BinaryOperator::BitXor => Instruction::BitXor,
            BinaryOperator::Shl => Instruction::Shl,
            BinaryOperator::Shr => Instruction::Shr,
        };
        builder.push_instructions([operator_instruction]);
        Ok(())
    }

    fn generate_unary_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        unary_expression: UnaryExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *unary_expression.operand)?;
        let operator_instruction = match unary_expression.operator {
            UnaryOperator::Neg => Instruction::Neg,
            UnaryOperator::Not => Instruction::Not,
            UnaryOperator::BitNot => Instruction::BitNot,
        };
        builder.push_instructions([operator_instruction]);
        Ok(())
    }

    fn generate_call_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        call_expression: CallExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *call_expression.callee)?;
        let arity = call_expression.arguments.len();
        for argument in call_expression.arguments {
            self.generate_expression(env, heap, builder, argument)?;
        }
        builder.push_instructions([Instruction::Call(arity.into())]);
        Ok(())
    }

    fn generate_member_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        member_expression: MemberExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *member_expression.object)?;
        let constant_index =
            env.add_constant(Value::string_in(heap, member_expression.member.identifier));
        builder.push_instructions([
            Instruction::Constant(constant_index),
            Instruction::ObjectGet,
        ]);
        Ok(())
    }

    fn generate_access_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        access_expression: AccessExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, heap, builder, *access_expression.object)?;
        self.generate_expression(env, heap, builder, *access_expression.key)?;
        builder.push_instructions([Instruction::ObjectGet]);
        Ok(())
    }

    fn generate_fn_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        fn_expression: FnExpression,
    ) -> Result<(), Error> {
        let arity = fn_expression.parameters.len().into();

        let function_builder = ChunkBuilderHandle::with_parent(builder.clone(), arity);
        function_builder.add_fresh_local("closure".to_string());

        // TODO: Optimise parameters that are `Pattern::Identifier` so they don't need this temp value.
        let parameter_stack_slots = fn_expression
            .parameters
            .iter()
            .map(|parameter| {
                (
                    function_builder.add_fresh_local("argument".to_string()),
                    parameter.clone(),
                )
            })
            .collect::<Vec<_>>();
        for (stack_slot, parameter) in parameter_stack_slots {
            function_builder.push_instructions([Instruction::Load(stack_slot)]);
            self.generate_pattern(env, heap, &function_builder, parameter)?;
        }

        self.generate_expression(env, heap, &function_builder, *fn_expression.body)?;

        // TODO: Handle closing of upvalues.
        function_builder.push_instructions([Instruction::Store(0.into())]);
        let scope = function_builder.pop_scope();
        for _ in 0..scope.locals.len() {
            function_builder.push_instructions([Instruction::Pop]);
        }
        function_builder.push_instructions([Instruction::Return]);

        let function = Function::new(function_builder.build());
        let function_index = env.add_function(function);
        builder.push_instructions([Instruction::Closure(function_index)]);
        Ok(())
    }

    fn generate_map_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        map_expression: MapExpression,
    ) -> Result<(), Error> {
        builder.push_instructions([Instruction::Map]);
        for MapExpressionPair { key, value, .. } in map_expression.pairs {
            builder.push_instructions([Instruction::Duplicate]);
            match key {
                MapExpressionKey::Identifier(identifier) => {
                    let constant_index =
                        env.add_constant(Value::string_in(heap, identifier.identifier));
                    builder.push_instructions([Instruction::Constant(constant_index)]);
                }
                MapExpressionKey::Expression(expression) => {
                    self.generate_expression(env, heap, builder, *expression)?;
                }
            }
            self.generate_expression(env, heap, builder, *value)?;
            builder.push_instructions([Instruction::ObjectSet, Instruction::Pop]);
        }
        Ok(())
    }

    fn generate_list_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        list_expression: ListExpression,
    ) -> Result<(), Error> {
        builder.push_instructions([Instruction::List]);
        let mut index = 0;
        for expression in list_expression.items {
            builder.push_instructions([Instruction::Duplicate, Instruction::Int(index.into())]);
            self.generate_expression(env, heap, builder, expression)?;
            builder.push_instructions([Instruction::ObjectSet, Instruction::Pop]);
            index += 1;
        }
        Ok(())
    }

    fn generate_identifier<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        identifier: Identifier,
    ) -> Result<(), Error> {
        if let Some(slot) = builder.local(&identifier.identifier) {
            builder.push_instructions([Instruction::Load(slot)]);
            Ok(())
        } else if let Some(index) = builder.resolve_upvalue(&identifier.identifier) {
            builder.push_instructions([Instruction::UpvalueLoad(index)]);
            Ok(())
        } else {
            unimplemented!()
        }
    }

    fn generate_literal<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        literal: Literal,
    ) -> Result<(), Error> {
        match literal {
            Literal::Bool(bool_literal) => {
                let bool_instruction = if bool_literal.value {
                    Instruction::True
                } else {
                    Instruction::False
                };
                builder.push_instructions([bool_instruction]);
                Ok(())
            }
            Literal::Int(int_literal) => {
                builder.push_instructions([Instruction::Int(IntImmediate(int_literal.value))]);
                Ok(())
            }
            Literal::Float(float_literal) => {
                let constant = env.add_constant(Value::Float(float_literal.value.into()));
                builder.push_instructions([Instruction::Constant(constant)]);
                Ok(())
            }
            _ => unimplemented!(),
        }
    }

    fn generate_pattern<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        pattern: Pattern,
    ) -> Result<(), Error> {
        match pattern {
            Pattern::Identifier(identifier) => {
                builder.add_local(identifier.identifier.clone());
            }
            Pattern::Wildcard(_) => {
                builder.push_instructions([Instruction::Pop]);
            }
            Pattern::List(list) => {
                builder.add_fresh_local("list_pattern".to_string());
                let mut index = 0;
                for pattern in list.items {
                    builder.push_instructions([
                        Instruction::Duplicate,
                        Instruction::Int(index.into()),
                        Instruction::ObjectGet,
                    ]);
                    self.generate_pattern(env, heap, builder, pattern)?;
                    index += 1;
                }
            }
            Pattern::Map(map) => {
                builder.add_fresh_local("map_pattern".to_string());
                for pair in map.pairs {
                    let constant_index =
                        env.add_constant(Value::string_in(heap, pair.key.identifier.clone()));
                    builder.push_instructions([
                        Instruction::Duplicate,
                        Instruction::Constant(constant_index),
                        Instruction::ObjectGet,
                    ]);
                    match pair.value {
                        Some(pattern) => self.generate_pattern(env, heap, builder, pattern)?,
                        None => self.generate_pattern(
                            env,
                            heap,
                            builder,
                            Pattern::Identifier(pair.key),
                        )?,
                    };
                }
            }
        }
        Ok(())
    }
}

struct ChunkBuilderHandle(Rc<RefCell<ChunkBuilder>>);

impl ChunkBuilderHandle {
    fn new(arity: Arity) -> ChunkBuilderHandle {
        ChunkBuilderHandle(Rc::new(RefCell::new(ChunkBuilder {
            parent: None,
            frame: Frame::new(),
            arity,
            upvalues: Vec::new(),
            instructions: Vec::new(),
        })))
    }

    fn with_parent(parent: ChunkBuilderHandle, arity: Arity) -> ChunkBuilderHandle {
        ChunkBuilderHandle(Rc::new(RefCell::new(ChunkBuilder {
            parent: Some(parent),
            frame: Frame::new(),
            arity,
            upvalues: Vec::new(),
            instructions: Vec::new(),
        })))
    }

    fn resolve_upvalue(&self, identifier: &str) -> Option<UpvalueIndex> {
        self.0.borrow_mut().resolve_upvalue(identifier)
    }

    fn add_local(&self, identifier: String) -> StackSlot {
        self.0.borrow_mut().add_local(identifier)
    }

    fn add_fresh_local(&self, prefix: String) -> StackSlot {
        self.0.borrow_mut().add_fresh_local(prefix)
    }

    fn local(&self, identifier: &str) -> Option<StackSlot> {
        self.0.borrow().local(identifier)
    }

    fn push_scope(&self) {
        self.0.borrow_mut().push_scope();
    }

    fn pop_scope(&self) -> Scope {
        self.0.borrow_mut().pop_scope()
    }

    fn push_instructions<I>(&self, instructions: I)
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.0.borrow_mut().push_instructions(instructions);
    }

    fn build(&self) -> Chunk {
        self.0.borrow().build()
    }
}

impl Clone for ChunkBuilderHandle {
    fn clone(&self) -> Self {
        ChunkBuilderHandle(Rc::clone(&self.0))
    }
}

// we can't just use a simple mutable borrow here because of this issue: `Option<&'p mut ChunkBuilder<???>>`.
struct ChunkBuilder {
    parent: Option<ChunkBuilderHandle>,
    frame: Frame,
    arity: Arity,
    upvalues: Vec<Upvalue>,
    instructions: Vec<Instruction>,
}

impl ChunkBuilder {
    fn instruction_offset(&self) -> InstructionOffset {
        self.instructions.len().into()
    }

    fn resolve_upvalue(&mut self, identifier: &str) -> Option<UpvalueIndex> {
        self.frame.upvalue(identifier).or_else(|| {
            self.parent.as_ref().cloned().and_then(|parent| {
                if let Some(slot) = parent.local(identifier) {
                    Some(self.add_upvalue(Upvalue::Local(slot)))
                } else if let Some(index) = parent.resolve_upvalue(identifier) {
                    Some(self.add_upvalue(Upvalue::Upvalue(index)))
                } else {
                    None
                }
            })
        })
    }

    fn add_local(&mut self, identifier: String) -> StackSlot {
        self.frame.add_local(identifier)
    }

    fn add_fresh_local(&mut self, prefix: String) -> StackSlot {
        self.frame.add_fresh_local(prefix)
    }

    fn local(&self, identifier: &str) -> Option<StackSlot> {
        self.frame.local(identifier)
    }

    fn add_upvalue(&mut self, upvalue: Upvalue) -> UpvalueIndex {
        let index = UpvalueIndex::from(self.upvalues.len());
        self.upvalues.push(upvalue);
        index
    }

    fn push_scope(&mut self) {
        self.frame.push_scope();
    }

    fn pop_scope(&mut self) -> Scope {
        self.frame.pop_scope()
    }

    fn push_instructions<I>(&mut self, instructions: I)
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.instructions.extend(instructions);
    }

    fn build(&self) -> Chunk {
        Chunk {
            arity: self.arity,
            upvalues: self.upvalues.clone().into(),
            instructions: self.instructions.clone().into(),
        }
    }
}

struct Frame {
    upvalues: HashMap<String, UpvalueIndex>,
    scopes: Vec<Scope>,
}

impl Frame {
    fn new() -> Frame {
        Frame {
            upvalues: HashMap::new(),
            scopes: vec![Scope::new(0)],
        }
    }

    fn upvalue(&self, identifier: &str) -> Option<UpvalueIndex> {
        self.upvalues.get(identifier).copied()
    }

    fn add_upvalue(&mut self, identifier: String, index: UpvalueIndex) {
        self.upvalues.insert(identifier, index);
    }

    fn local(&self, identifier: &str) -> Option<StackSlot> {
        for scope in self.scopes.iter().rev() {
            if let Some(slot) = scope.local(identifier) {
                return Some(slot);
            }
        }
        None
    }

    fn add_local(&mut self, identifier: String) -> StackSlot {
        self.scopes.last_mut().unwrap().add_local(identifier)
    }

    fn add_fresh_local(&mut self, prefix: String) -> StackSlot {
        self.scopes.last_mut().unwrap().add_fresh_local(prefix)
    }

    fn push_scope(&mut self) {
        self.scopes.push(Scope::new(
            self.scopes.last().unwrap().base + self.scopes.len(),
        ));
    }

    fn pop_scope(&mut self) -> Scope {
        let scope = self.scopes.pop();
        scope.unwrap()
    }
}

struct Scope {
    base: usize,
    locals: HashMap<String, StackSlot>,
    fresh_counter: usize,
}

impl Scope {
    fn new(base: usize) -> Scope {
        Scope {
            base,
            locals: HashMap::new(),
            fresh_counter: 0,
        }
    }

    fn local(&self, identifer: &str) -> Option<StackSlot> {
        self.locals.get(identifer).copied()
    }

    fn add_local(&mut self, identifer: String) -> StackSlot {
        let slot = StackSlot::from(self.base + self.locals.len());
        self.locals.insert(identifer, slot);
        slot
    }

    fn add_fresh_local(&mut self, prefix: String) -> StackSlot {
        self.add_local(format!("__{}_{}", prefix, self.fresh_counter))
    }
}
