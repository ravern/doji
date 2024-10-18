use std::{cell::RefCell, collections::HashMap, rc::Rc};

use crate::{
    ast::{
        BinaryExpression, BinaryOperator, Block, Expression, Identifier, LetStatement, Literal,
        Module, Pattern, Statement,
    },
    bytecode::{Chunk, CodeOffset, Instruction, IntImmediate, StackSlot, Upvalue, UpvalueIndex},
    env::Environment,
    error::Error,
    parse::Parser,
    value::Function,
};

pub struct Compiler {}

impl Compiler {
    pub fn compile<'gc>(
        &mut self,
        env: &Environment<'gc>,
        source: &str,
    ) -> Result<Function, Error> {
        let module = Parser {}.parse(source).unwrap();
        Generator {}.generate_module(env, module)
    }
}

struct Generator {}

impl Generator {
    fn generate_module<'gc>(
        &self,
        env: &Environment<'gc>,
        module: Module,
    ) -> Result<Function, Error> {
        let builder = ChunkBuilderHandle::new();
        self.generate_block(env, &builder, module.block)?;
        builder.push_code([
            Instruction::Store(StackSlot::from(0)),
            Instruction::Pop,
            Instruction::Return,
        ]);
        Ok(Function::new(0, builder.build()))
    }

    fn generate_block<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        block: Block,
    ) -> Result<(), Error> {
        builder.push_scope();
        builder.add_local("<block>".to_string());
        builder.push_code([Instruction::Nil]);
        for statement in block.statements {
            self.generate_statement(env, builder, statement)?;
        }
        if let Some(expression) = block.return_expression {
            self.generate_expression(env, builder, *expression)?;
        } else {
            builder.push_code([Instruction::Nil]);
        }
        let scope = builder.pop_scope();
        builder.push_code([Instruction::Store(StackSlot::from(scope.base))]);
        for _ in 0..scope.locals.len() {
            builder.push_code([Instruction::Pop]);
        }
        Ok(())
    }

    fn generate_statement<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        statement: Statement,
    ) -> Result<(), Error> {
        match statement {
            Statement::Let(let_statement) => {
                self.generate_let_statement(env, builder, let_statement)
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
                self.generate_expression(env, builder, expression)?;
                builder.push_code([Instruction::Pop]);
                Ok(())
            }
            _ => unimplemented!(),
        }
    }

    fn generate_let_statement<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        let_statement: LetStatement,
    ) -> Result<(), Error> {
        let pattern = let_statement.pattern;
        let value = let_statement.value;
        match &*pattern {
            Pattern::Identifier(identifier) => {
                builder.add_local(identifier.identifier.clone());
                self.generate_expression(env, builder, *value)?;
                Ok(())
            }
            _ => unimplemented!(),
        }
    }

    fn generate_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        expression: Expression,
    ) -> Result<(), Error> {
        match expression {
            Expression::Binary(binary_expression) => {
                self.generate_binary_expression(env, builder, binary_expression)
            }
            // Expression::Unary(unary_expression) => {
            //     self.generate_unary_expression(env, builder, unary_expression)
            // }
            // Expression::Call(call_expression) => {
            //     self.generate_call_expression(env, builder, call_expression)
            // }
            // Expression::Member(member_expression) => {
            //     self.generate_member_expression(env, builder, member_expression)
            // }
            // Expression::Access(access_expression) => {
            //     self.generate_access_expression(env, builder, access_expression)
            // }
            // Expression::If(if_expression) => {
            //     self.generate_if_expression(env, builder, if_expression)
            // }
            // Expression::Fn(fn_expression) => {
            //     self.generate_fn_expression(env, builder, fn_expression)
            // }
            // Expression::Map(map_expression) => {
            //     self.generate_map_expression(env, builder, map_expression)
            // }
            // Expression::List(list_expression) => {
            //     self.generate_list_expression(env, builder, list_expression)
            // }
            // Expression::Block(block) => self.generate_block(env, builder, block),
            Expression::Identifier(identifier) => {
                self.generate_identifier(env, builder, identifier)
            }
            Expression::Literal(literal) => self.generate_literal(env, builder, literal),
            _ => unimplemented!(),
        }
    }

    fn generate_binary_expression<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        binary_expression: BinaryExpression,
    ) -> Result<(), Error> {
        self.generate_expression(env, builder, *binary_expression.left)?;
        self.generate_expression(env, builder, *binary_expression.right)?;
        match binary_expression.operator {
            BinaryOperator::Add => builder.push_code([Instruction::Add]),
            BinaryOperator::Sub => builder.push_code([Instruction::Sub]),
            BinaryOperator::Mul => builder.push_code([Instruction::Mul]),
            BinaryOperator::Div => builder.push_code([Instruction::Div]),
            BinaryOperator::Rem => builder.push_code([Instruction::Rem]),
            BinaryOperator::Eq => builder.push_code([Instruction::Eq]),
            BinaryOperator::Neq => builder.push_code([Instruction::Neq]),
            BinaryOperator::Gt => builder.push_code([Instruction::Gt]),
            BinaryOperator::Gte => builder.push_code([Instruction::Gte]),
            BinaryOperator::Lt => builder.push_code([Instruction::Lt]),
            BinaryOperator::Lte => builder.push_code([Instruction::Lte]),
            BinaryOperator::And => builder.push_code([Instruction::And]),
            BinaryOperator::Or => builder.push_code([Instruction::Or]),
            BinaryOperator::BitAnd => builder.push_code([Instruction::BitAnd]),
            BinaryOperator::BitOr => builder.push_code([Instruction::BitOr]),
            BinaryOperator::BitXor => builder.push_code([Instruction::BitXor]),
            BinaryOperator::Shl => builder.push_code([Instruction::Shl]),
            BinaryOperator::Shr => builder.push_code([Instruction::Shr]),
        }
        Ok(())
    }

    fn generate_identifier<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        identifier: Identifier,
    ) -> Result<(), Error> {
        if let Some(slot) = builder.local(&identifier.identifier) {
            builder.push_code([Instruction::Load(slot)]);
            Ok(())
        } else if let Some(index) = builder.resolve_upvalue(&identifier.identifier) {
            builder.push_code([Instruction::UpvalueLoad(index)]);
            Ok(())
        } else {
            unimplemented!()
        }
    }

    fn generate_literal<'gc>(
        &self,
        env: &Environment<'gc>,
        builder: &ChunkBuilderHandle,
        literal: Literal,
    ) -> Result<(), Error> {
        match literal {
            Literal::Int(int_literal) => {
                builder.push_code([Instruction::Int(IntImmediate(int_literal.value))]);
                Ok(())
            }
            _ => unimplemented!(),
        }
    }
}

struct ChunkBuilderHandle(Rc<RefCell<ChunkBuilder>>);

impl ChunkBuilderHandle {
    fn new() -> ChunkBuilderHandle {
        ChunkBuilderHandle(Rc::new(RefCell::new(ChunkBuilder {
            parent: None,
            frame: Frame::new(),
            upvalues: Vec::new(),
            code: Vec::new(),
        })))
    }

    fn with_parent(parent: ChunkBuilderHandle) -> ChunkBuilderHandle {
        ChunkBuilderHandle(Rc::new(RefCell::new(ChunkBuilder {
            parent: Some(parent),
            frame: Frame::new(),
            upvalues: Vec::new(),
            code: Vec::new(),
        })))
    }

    fn resolve_upvalue(&self, identifier: &str) -> Option<UpvalueIndex> {
        self.0.borrow_mut().resolve_upvalue(identifier)
    }

    fn add_local(&self, identifier: String) -> StackSlot {
        self.0.borrow_mut().add_local(identifier)
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

    fn push_code<I>(&self, instructions: I)
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.0.borrow_mut().push_code(instructions);
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

struct ChunkBuilder {
    parent: Option<ChunkBuilderHandle>,
    frame: Frame,
    upvalues: Vec<Upvalue>,
    code: Vec<Instruction>,
}

impl ChunkBuilder {
    fn code_offset(&self) -> CodeOffset {
        self.code.len().into()
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

    fn push_code<I>(&mut self, instructions: I)
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.code.extend(instructions);
    }

    fn build(&self) -> Chunk {
        Chunk {
            upvalues: self.upvalues.clone().into(),
            code: self.code.clone().into(),
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
}

impl Scope {
    fn new(base: usize) -> Scope {
        Scope {
            base,
            locals: HashMap::new(),
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
}
