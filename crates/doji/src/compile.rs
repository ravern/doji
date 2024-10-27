use std::{cell::RefCell, collections::HashMap, rc::Rc};

use crate::{
    ast::{
        AccessExpression, BinaryExpression, BinaryOperator, Block, CallExpression, Expression,
        FnExpression, Identifier, IfExpression, LetStatement, ListExpression, Literal,
        MapExpression, MapExpressionKey, MapExpressionPair, MemberExpression, Module, Pattern,
        ReturnStatement, Statement, UnaryExpression, UnaryOperator,
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
        let module = dbg!(Parser {}.parse(source).unwrap());
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
        builder.add_fresh_local("module".to_string());
        self.generate_block(env, heap, &builder, module.block)?;
        builder.push_instructions([Instruction::Store(0.into()), Instruction::Return]);
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
        builder.push_instructions([Instruction::Store(scope.base.into())]);
        builder.push_instructions(self.close_scope(scope)?);
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
            Statement::Return(return_statement) => {
                self.generate_return_statement(env, heap, builder, return_statement)
            }
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
            Statement::IfExpressionSemi(if_expression_semi) => {
                self.generate_expression(
                    env,
                    heap,
                    builder,
                    Expression::If(if_expression_semi.expression),
                )?;
                builder.push_instructions([Instruction::Pop]);
                Ok(())
            }
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
        self.build_let_scope(builder, *let_statement.pattern.clone());
        self.generate_expression(env, heap, builder, *let_statement.value)?;
        let let_scope = builder.reset_let_scope();
        self.generate_pattern(env, heap, builder, *let_statement.pattern)?;
        for (identifier, local) in let_scope.locals {
            if local.is_upvalue {
                builder.mark_local_as_upvalue(&identifier);
            }
        }
        Ok(())
    }

    fn generate_return_statement<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        return_statement: ReturnStatement,
    ) -> Result<(), Error> {
        if let Some(value) = return_statement.value {
            self.generate_expression(env, heap, builder, *value)?;
        } else {
            builder.push_instructions([Instruction::Nil]);
        }
        let scopes = builder.0.borrow().frame.scopes.clone();
        for scope in scopes.into_iter().rev() {
            dbg!(&scope);
            builder.push_instructions([Instruction::Store(scope.base.into())]);
            builder.push_instructions(self.close_scope(scope)?);
        }
        builder.push_instructions([Instruction::Return]);
        Ok(())
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
            Expression::If(if_expression) => {
                self.generate_if_expression(env, heap, builder, if_expression)
            }
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

    fn generate_if_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        if_expression: IfExpression,
    ) -> Result<(), Error> {
        let mut skip_else_jumps = Vec::new();

        self.generate_expression(env, heap, builder, *if_expression.condition)?;
        builder.push_instructions([Instruction::Test]);
        let skip_if_jump = builder.instruction_offset();
        builder.push_instructions([Instruction::Jump(0.into())]);
        self.generate_block(env, heap, builder, if_expression.if_body)?;
        skip_else_jumps.push(builder.instruction_offset());
        builder.push_instructions([Instruction::Jump(0.into())]);
        builder.set_jump_instruction_target(skip_if_jump);

        for else_if in if_expression.else_ifs {
            self.generate_expression(env, heap, builder, *else_if.condition)?;
            builder.push_instructions([Instruction::Test]);
            let skip_if_jump = builder.instruction_offset();
            builder.push_instructions([Instruction::Jump(0.into())]);
            self.generate_block(env, heap, builder, else_if.body)?;
            skip_else_jumps.push(builder.instruction_offset());
            builder.push_instructions([Instruction::Jump(0.into())]);
            builder.set_jump_instruction_target(skip_if_jump);
        }

        if let Some(else_body) = if_expression.else_body {
            self.generate_block(env, heap, builder, else_body)?;
        } else {
            builder.push_instructions([Instruction::Nil]);
        }
        for skip_else_jump in skip_else_jumps {
            builder.set_jump_instruction_target(skip_else_jump);
        }

        Ok(())
    }

    fn generate_fn_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        builder: &ChunkBuilderHandle,
        fn_expression: FnExpression,
    ) -> Result<(), Error> {
        dbg!(&builder.0.borrow().frame.let_scope);
        builder.push_let_scope();

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
        function_builder.push_instructions(self.close_scope(function_builder.pop_scope())?);
        function_builder.push_instructions([Instruction::Return]);

        let function = Function::new(dbg!(function_builder.build()));
        let function_index = env.add_function(function);
        builder.push_instructions([Instruction::Closure(function_index)]);

        builder.pop_let_scope();

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
        if let Some(local) = builder.local(&identifier.identifier) {
            builder.push_instructions([Instruction::Load(local.slot)]);
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
                let slot = builder.add_fresh_local("list_pattern".to_string());
                let mut index = 0;
                for pattern in list.items {
                    builder.push_instructions([
                        Instruction::Load(slot),
                        Instruction::Int(index.into()),
                        Instruction::ObjectGet,
                    ]);
                    self.generate_pattern(env, heap, builder, pattern)?;
                    index += 1;
                }
            }
            Pattern::Map(map) => {
                let slot = builder.add_fresh_local("map_pattern".to_string());
                for pair in map.pairs {
                    let constant_index =
                        env.add_constant(Value::string_in(heap, pair.key.identifier.clone()));
                    builder.push_instructions([
                        Instruction::Load(slot),
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

    fn build_let_scope<'gc>(&self, builder: &ChunkBuilderHandle, pattern: Pattern) {
        match pattern {
            Pattern::Identifier(identifier) => {
                builder.add_let_local(identifier.identifier.clone());
            }
            Pattern::Wildcard(_) => {
                builder.push_instructions([Instruction::Pop]);
            }
            Pattern::List(list) => {
                builder.add_fresh_let_local("list_pattern".to_string());
                for pattern in list.items {
                    self.build_let_scope(builder, pattern);
                }
            }
            Pattern::Map(map) => {
                builder.add_fresh_let_local("map_pattern".to_string());
                for pair in map.pairs {
                    let pattern = match pair.value {
                        Some(pattern) => pattern,
                        None => Pattern::Identifier(pair.key),
                    };
                    self.build_let_scope(builder, pattern);
                }
            }
        }
    }

    fn close_scope<'gc>(&self, scope: Scope) -> Result<Vec<Instruction>, Error> {
        let mut instructions = vec![Instruction::Pop; scope.locals.len() - 1];
        dbg!(&scope);
        for (_, local) in scope.locals {
            // We're not popping the 0th slot because that's the return value.
            if local.slot == 0.into() {
                continue;
            }
            if local.is_upvalue {
                let index = instructions.len() - (local.slot.into_usize() - scope.base);
                instructions[index] = Instruction::UpvalueClose;
            }
        }
        Ok(instructions)
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

    fn instruction_offset(&self) -> InstructionOffset {
        self.0.borrow().instruction_offset()
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

    fn add_let_local(&self, identifier: String) -> StackSlot {
        self.0.borrow_mut().add_let_local(identifier)
    }

    fn add_fresh_let_local(&self, prefix: String) -> StackSlot {
        self.0.borrow_mut().add_fresh_let_local(prefix)
    }

    fn reset_let_scope(&self) -> Scope {
        self.0.borrow_mut().reset_let_scope()
    }

    fn push_let_scope(&self) {
        self.0.borrow_mut().push_let_scope();
    }

    fn pop_let_scope(&self) {
        self.0.borrow_mut().pop_let_scope();
    }

    fn local(&self, identifier: &str) -> Option<Local> {
        self.0.borrow().local(identifier)
    }

    fn mark_local_as_upvalue(&self, identifier: &str) {
        self.0.borrow_mut().mark_local_as_upvalue(identifier);
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

    fn set_jump_instruction_target(&self, jump_offset: InstructionOffset) {
        self.0.borrow_mut().set_jump_instruction_target(jump_offset);
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
                if let Some(local) = parent.local(identifier) {
                    parent.mark_local_as_upvalue(identifier);
                    Some(self.add_upvalue(Upvalue::Local(local.slot)))
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

    fn add_let_local(&mut self, identifier: String) -> StackSlot {
        self.frame.add_let_local(identifier)
    }

    fn add_fresh_let_local(&mut self, prefix: String) -> StackSlot {
        self.frame.add_fresh_let_local(prefix)
    }

    fn reset_let_scope(&mut self) -> Scope {
        self.frame.reset_let_scope()
    }

    fn push_let_scope(&mut self) {
        self.frame.push_let_scope();
    }

    fn pop_let_scope(&mut self) {
        self.frame.pop_let_scope();
    }

    fn local(&self, identifier: &str) -> Option<Local> {
        self.frame.local(identifier)
    }

    fn mark_local_as_upvalue(&mut self, identifier: &str) {
        self.frame.mark_local_as_upvalue(identifier);
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

    fn set_jump_instruction_target(&mut self, jump_offset: InstructionOffset) {
        let offset = self.instruction_offset();
        let instruction = self.instructions.get_mut(jump_offset.into_usize()).unwrap();
        if let Instruction::Jump(ref mut target) = instruction {
            *target = offset;
        }
    }

    fn build(&self) -> Chunk {
        Chunk {
            arity: self.arity,
            upvalues: self.upvalues.clone().into(),
            instructions: self.instructions.clone().into(),
        }
    }
}

#[derive(Debug)]
struct Frame {
    upvalues: HashMap<String, UpvalueIndex>,
    scopes: Vec<Scope>,
    let_scope: Option<Scope>,
    is_let_scope_pushed: bool,
}

impl Frame {
    fn new() -> Frame {
        Frame {
            upvalues: HashMap::new(),
            scopes: vec![Scope::new(0)],
            let_scope: None,
            is_let_scope_pushed: false,
        }
    }

    fn upvalue(&self, identifier: &str) -> Option<UpvalueIndex> {
        self.upvalues.get(identifier).copied()
    }

    fn add_upvalue(&mut self, identifier: String, index: UpvalueIndex) {
        self.upvalues.insert(identifier, index);
    }

    fn local(&self, identifier: &str) -> Option<Local> {
        for scope in self.scopes.iter().rev() {
            if let Some(local) = scope.local(identifier) {
                return Some(local);
            }
        }
        None
    }

    fn mark_local_as_upvalue(&mut self, identifier: &str) {
        for scope in self.scopes.iter_mut().rev() {
            if scope.local(identifier).is_some() {
                scope.mark_local_as_upvalue(identifier);
            }
        }
    }

    fn add_local(&mut self, identifier: String) -> StackSlot {
        self.scopes.last_mut().unwrap().add_local(identifier)
    }

    fn add_fresh_local(&mut self, prefix: String) -> StackSlot {
        self.scopes.last_mut().unwrap().add_fresh_local(prefix)
    }

    fn add_let_local(&mut self, identifier: String) -> StackSlot {
        if let Some(let_scope) = &mut self.let_scope {
            let_scope.add_local(identifier)
        } else {
            self.let_scope = Some(Scope::new(
                self.scopes.last().unwrap().base + self.scopes.last().unwrap().locals.len(),
            ));
            self.add_let_local(identifier)
        }
    }

    fn add_fresh_let_local(&mut self, prefix: String) -> StackSlot {
        if let Some(let_scope) = &mut self.let_scope {
            let_scope.add_fresh_local(prefix)
        } else {
            self.let_scope = Some(Scope::new(
                self.scopes.last().unwrap().base + self.scopes.last().unwrap().locals.len(),
            ));
            self.add_fresh_let_local(prefix)
        }
    }

    fn reset_let_scope(&mut self) -> Scope {
        self.let_scope.take().unwrap()
    }

    fn push_let_scope(&mut self) {
        if let Some(let_scope) = self.let_scope.take() {
            self.scopes.push(let_scope);
            self.is_let_scope_pushed = true;
        }
    }

    fn pop_let_scope(&mut self) {
        if self.is_let_scope_pushed {
            let scope = self.scopes.pop();
            self.let_scope = Some(scope.unwrap());
            self.is_let_scope_pushed = false;
        }
    }

    fn push_scope(&mut self) {
        self.scopes.push(Scope::new(
            self.scopes.last().unwrap().base + self.scopes.last().unwrap().locals.len(),
        ));
    }

    fn pop_scope(&mut self) -> Scope {
        let scope = self.scopes.pop();
        scope.unwrap()
    }
}

#[derive(Clone, Debug)]
struct Scope {
    base: usize,
    locals: HashMap<String, Local>,
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

    fn local(&self, identifer: &str) -> Option<Local> {
        self.locals.get(identifer).cloned()
    }

    fn mark_local_as_upvalue(&mut self, identifier: &str) {
        if let Some(local) = self.locals.get_mut(identifier) {
            local.is_upvalue = true;
        }
    }

    fn add_local(&mut self, identifer: String) -> StackSlot {
        let slot = StackSlot::from(self.base + self.locals.len());
        self.locals.insert(identifer, Local::new(slot));
        slot
    }

    fn add_fresh_local(&mut self, prefix: String) -> StackSlot {
        let slot = self.add_local(format!("__{}_{}", prefix, self.fresh_counter));
        self.fresh_counter += 1;
        slot
    }
}

#[derive(Clone, Debug)]
struct Local {
    slot: StackSlot,
    is_upvalue: bool,
}

impl Local {
    fn new(slot: StackSlot) -> Local {
        Local {
            slot,
            is_upvalue: false,
        }
    }
}
