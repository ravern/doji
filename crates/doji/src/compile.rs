use std::{cell::RefCell, collections::HashMap, rc::Rc};

use once_cell::sync::Lazy;
use pest::{
    iterators::{Pair, Pairs},
    pratt_parser::{Assoc, Op, PrattParser},
    Parser as _,
};
use pest_derive::Parser;

use crate::{
    ast::{
        AccessExpression, BinaryExpression, BinaryOperator, Block, BoolLiteral, CallExpression,
        Expression, FloatLiteral, FnExpression, ForStatement, Identifier, IfElseIf, IfExpression,
        IntLiteral, LetStatement, ListExpression, ListPattern, Literal, MapExpression,
        MapExpressionKey, MapExpressionPair, MapPattern, MapPatternPair, MemberExpression, Module,
        Pattern, ReturnStatement, Span, Statement, UnaryExpression, UnaryOperator, WhileStatement,
    },
    bytecode::{Chunk, CodeOffset, Instruction, IntImmediate, StackSlot, Upvalue, UpvalueIndex},
    env::Environment,
    error::Error,
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
    // let index_two = env.add_constant(Value::Int(2));
    // let index_four = env.add_constant(Value::Int(4));
    // let index_add = env.add_constant(Value::NativeFunction(NativeFunctionHandle::new(
    //     2,
    //     |env, heap, stack| {
    //         let right = stack.pop().unwrap();
    //         let left = stack.pop().unwrap();
    //         match (&left, &right) {
    //             (Value::Int(left), Value::Int(right)) => {
    //                 stack.set(StackSlot::from(0), Value::Int(left + right));
    //                 Ok(())
    //             }
    //             _ => Err(Error::new(
    //                 ErrorContext {
    //                     code_offset: CodeOffset::from(0),
    //                 },
    //                 ErrorKind::WrongType(TypeError {
    //                     expected: [ValueType::Int].into(),
    //                     found: left.ty(),
    //                 }),
    //             )),
    //         }
    //     },
    // )));
    // Ok(Function::new(
    //     0,
    //     ChunkBuilder::new()
    //         .code([
    //             Instruction::Constant(index_add),
    //             Instruction::Constant(index_two),
    //             Instruction::Constant(index_four),
    //             Instruction::Call(2),
    //             Instruction::Store(StackSlot::from(0)),
    //             Instruction::Return,
    //         ])
    //         .build(),
    // ))

    // Ok(Function::new(
    //     0,
    //     ChunkBuilder::new()
    //         .code([
    //             Instruction::Closure(
    //                 env.add_function(Function::new(
    //                     2,
    //                     ChunkBuilder::new()
    //                         .code([
    //                             Instruction::Closure(
    //                                 env.add_function(Function::new(
    //                                     0,
    //                                     ChunkBuilder::new()
    //                                         .code([
    //                                             Instruction::UpvalueLoad(UpvalueIndex::from(0)),
    //                                             Instruction::UpvalueLoad(UpvalueIndex::from(1)),
    //                                             Instruction::Add,
    //                                             Instruction::Store(StackSlot::from(0)),
    //                                             Instruction::Return,
    //                                         ])
    //                                         .upvalue(Upvalue::Local(StackSlot::from(1)))
    //                                         .upvalue(Upvalue::Local(StackSlot::from(2)))
    //                                         .build(),
    //                                 )),
    //                             ),
    //                             Instruction::Store(StackSlot::from(0)),
    //                             Instruction::UpvalueClose,
    //                             Instruction::UpvalueClose,
    //                             Instruction::Return,
    //                         ])
    //                         .build(),
    //                 )),
    //             ),
    //             Instruction::Constant(env.add_constant(Value::Int(34))),
    //             Instruction::Constant(env.add_constant(Value::Int(45))),
    //             Instruction::Call(2),
    //             Instruction::Call(0),
    //             Instruction::Store(StackSlot::from(0)),
    //             Instruction::Return,
    //         ])
    //         .build(),
    // ))
    // }
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

#[derive(Debug)]
struct ParseError {
    span: Span,
}

impl From<PestError> for ParseError {
    fn from(error: PestError) -> Self {
        ParseError {
            span: Span { start: 0, end: 0 },
        }
    }
}

macro_rules! take {
    ($self:ident, $pairs:ident, $rule:ident, $func:ident$(,)?) => {{
        let pair = $pairs.next().unwrap();
        if pair.as_rule() != Rule::$rule {
            unreachable!()
        }
        $self.$func(pair)
    }};
}

macro_rules! take_if {
    ($self:ident, $pairs:ident, $rule:ident, $func:ident$(,)?) => {
        if let Some(Rule::$rule) = $pairs.peek().map(|pair| pair.as_rule()) {
            $self
                .$func($pairs.next().unwrap())
                .map(|result| Some(result))
        } else {
            Ok(None)
        }
    };
}

macro_rules! take_while {
    ($self:ident, $pairs:ident, $rule:ident, $func:ident$(,)?) => {{
        let mut results = Ok(Vec::new());
        while let Some(Rule::$rule) = $pairs.peek().map(|pair| pair.as_rule()) {
            match $self.$func($pairs.next().unwrap()) {
                Ok(result) => results.as_mut().unwrap().push(result),
                Err(error) => {
                    results = Err(error);
                    break;
                }
            }
        }
        results.map(Into::into)
    }};
}

struct Parser {}

impl Parser {
    pub fn parse(&self, source: &str) -> Result<Module, ParseError> {
        let mut pairs = PestParser::parse(Rule::module, source)?;
        take!(self, pairs, module, parse_module)
    }

    fn parse_module<'i>(&self, pair: PestPair<'i>) -> Result<Module, ParseError> {
        let block = self.parse_block(pair)?;
        Ok(Module { block })
    }

    fn parse_block<'i>(&self, pair: PestPair<'i>) -> Result<Block, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Block {
            span,
            statements: take_while!(self, pairs, statement, parse_statement)?,
            return_expression: take_if!(self, pairs, expression, parse_expression)?.map(Box::new),
        })
    }

    fn parse_statement<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let pair = pair.into_inner().next().unwrap();
        match pair.as_rule() {
            Rule::let_statement => self.parse_let_statement(pair),
            Rule::for_statement => self.parse_for_statement(pair),
            Rule::while_statement => self.parse_while_statement(pair),
            Rule::return_statement => self.parse_return_statement(pair),
            Rule::break_statement => Ok(Statement::Break(pair.as_span().into())),
            Rule::continue_statement => Ok(Statement::Continue(pair.as_span().into())),
            Rule::expression => self.parse_expression(pair).map(Statement::Expression),
            _ => unreachable!(),
        }
    }

    fn parse_let_statement<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Statement::Let(LetStatement {
            span,
            pattern: take!(self, pairs, pattern, parse_pattern)?.into(),
            value: take!(self, pairs, expression, parse_expression)?.into(),
        }))
    }

    fn parse_for_statement<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Statement::For(ForStatement {
            span,
            pattern: take!(self, pairs, pattern, parse_pattern)?.into(),
            iterable: take!(self, pairs, expression, parse_expression)?.into(),
            body: take!(self, pairs, block, parse_block)?,
        }))
    }

    fn parse_while_statement<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Statement::While(WhileStatement {
            span,
            condition: take!(self, pairs, expression, parse_expression)?.into(),
            body: take!(self, pairs, block, parse_block)?,
        }))
    }

    fn parse_return_statement<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Statement::Return(ReturnStatement {
            span,
            value: take_if!(self, pairs, expression, parse_expression)?.map(Box::new),
        }))
    }

    fn parse_expression<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let pairs = pair.into_inner();
        let expr = PRATT_PARSER
            .map_primary(|pair| self.parse_primary(pair))
            .map_prefix(|op, expr| self.parse_prefix(op, expr?))
            .map_infix(|left, op, right| self.parse_infix(left?, op, right?))
            .map_postfix(|expr, op| self.parse_postfix(expr?, op))
            .parse(pairs)?;
        Ok(expr)
    }

    fn parse_primary<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let pair = pair.into_inner().next().unwrap();
        match pair.as_rule() {
            Rule::group => self.parse_group(pair),
            Rule::block => self.parse_block(pair).map(Expression::Block),
            Rule::if_expression => self.parse_if_expression(pair),
            Rule::fn_expression => self.parse_fn_expression(pair),
            Rule::map_expression => self.parse_map_expression(pair),
            Rule::list_expression => self.parse_list_expression(pair),
            Rule::identifier => self.parse_identifier(pair).map(Expression::Identifier),
            Rule::literal => self.parse_literal(pair).map(Expression::Literal),
            _ => unreachable!(),
        }
    }

    fn parse_if_expression<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner().peekable();
        Ok(Expression::If(IfExpression {
            span,
            condition: take!(self, pairs, expression, parse_expression)?.into(),
            if_body: take!(self, pairs, block, parse_block)?,
            else_ifs: take_while!(self, pairs, if_else_if, parse_if_else_if)?,
            else_body: take_if!(self, pairs, block, parse_block)?,
        }))
    }

    fn parse_fn_expression<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner().peekable();
        Ok(Expression::Fn(FnExpression {
            span,
            parameters: take_while!(self, pairs, pattern, parse_pattern)?,
            body: take!(self, pairs, expression, parse_expression)?.into(),
        }))
    }

    fn parse_map_expression<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Expression::Map(MapExpression {
            span,
            pairs: take_while!(self, pairs, map_expression_pair, parse_map_expression_pair)?,
        }))
    }

    fn parse_map_expression_pair<'i>(
        &self,
        pair: PestPair<'i>,
    ) -> Result<MapExpressionPair, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        let key_pair = pairs.next().unwrap();
        match key_pair.as_rule() {
            Rule::identifier => {
                let key = self.parse_identifier(key_pair)?;
                let value = take_if!(self, pairs, expression, parse_expression)?
                    .unwrap_or_else(|| Expression::Identifier(key.clone()))
                    .into();
                Ok(MapExpressionPair {
                    span,
                    key: MapExpressionKey::Identifier(key),
                    value,
                })
            }
            Rule::expression => Ok(MapExpressionPair {
                span,
                key: MapExpressionKey::Expression(self.parse_expression(key_pair)?.into()),
                value: take!(self, pairs, expression, parse_expression)?.into(),
            }),
            _ => unreachable!(),
        }
    }

    fn parse_list_expression<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        Ok(Expression::List(ListExpression {
            span,
            items: take_while!(self, pairs, expression, parse_expression)?,
        }))
    }

    fn parse_if_else_if<'i>(&self, pair: PestPair<'i>) -> Result<IfElseIf, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner().peekable();
        Ok(IfElseIf {
            span,
            condition: take!(self, pairs, expression, parse_expression)?.into(),
            body: take!(self, pairs, block, parse_block)?,
        })
    }

    fn parse_group<'i>(&self, pair: PestPair<'i>) -> Result<Expression, ParseError> {
        let mut pairs = pair.into_inner();
        take!(self, pairs, expression, parse_expression)
    }

    fn parse_prefix<'i>(
        &self,
        operator: PestPair<'i>,
        operand: Expression,
    ) -> Result<Expression, ParseError> {
        let operator_span = Span::from(operator.as_span());
        let operator = match operator.as_rule() {
            Rule::neg => UnaryOperator::Neg,
            Rule::not => UnaryOperator::Not,
            Rule::bit_not => UnaryOperator::BitNot,
            _ => unreachable!(),
        };
        Ok(Expression::Unary(UnaryExpression {
            span: operator_span.join(&operand.span()),
            operator,
            operand: operand.into(),
        }))
    }

    fn parse_infix<'i>(
        &self,
        left: Expression,
        operator: PestPair<'i>,
        right: Expression,
    ) -> Result<Expression, ParseError> {
        let operator = match operator.as_rule() {
            Rule::add => BinaryOperator::Add,
            Rule::sub => BinaryOperator::Sub,
            Rule::mul => BinaryOperator::Mul,
            Rule::div => BinaryOperator::Div,
            Rule::rem => BinaryOperator::Rem,
            Rule::eq => BinaryOperator::Eq,
            Rule::neq => BinaryOperator::Neq,
            Rule::gt => BinaryOperator::Gt,
            Rule::gte => BinaryOperator::Gte,
            Rule::lt => BinaryOperator::Lt,
            Rule::lte => BinaryOperator::Lte,
            Rule::and => BinaryOperator::And,
            Rule::or => BinaryOperator::Or,
            Rule::bit_and => BinaryOperator::BitAnd,
            Rule::bit_or => BinaryOperator::BitOr,
            Rule::bit_xor => BinaryOperator::BitXor,
            Rule::shl => BinaryOperator::Shl,
            Rule::shr => BinaryOperator::Shr,
            _ => unreachable!(),
        };
        Ok(Expression::Binary(BinaryExpression {
            span: left.span().join(&right.span()),
            operator,
            left: left.into(),
            right: right.into(),
        }))
    }

    fn parse_postfix<'i>(
        &self,
        operand: Expression,
        operator: PestPair<'i>,
    ) -> Result<Expression, ParseError> {
        match operator.as_rule() {
            Rule::call_expression_postfix => self.parse_call_expression(operand, operator),
            Rule::member_expression_postfix => self.parse_member_expression(operand, operator),
            Rule::access_expression_postfix => self.parse_access_expression(operand, operator),
            _ => unreachable!(),
        }
    }

    fn parse_call_expression<'i>(
        &self,
        operand: Expression,
        operator: PestPair<'i>,
    ) -> Result<Expression, ParseError> {
        let operator_span = operator.as_span().into();
        let mut pairs = operator.into_inner().peekable();
        Ok(Expression::Call(CallExpression {
            span: operand.span().join(&operator_span),
            callee: operand.into(),
            arguments: take_while!(self, pairs, expression, parse_expression)?,
        }))
    }

    fn parse_member_expression<'i>(
        &self,
        operand: Expression,
        operator: PestPair<'i>,
    ) -> Result<Expression, ParseError> {
        let operator_span = operator.as_span().into();
        let mut pairs = operator.into_inner();
        Ok(Expression::Member(MemberExpression {
            span: operand.span().join(&operator_span),
            object: operand.into(),
            member: take!(self, pairs, identifier, parse_identifier)?.into(),
        }))
    }

    fn parse_access_expression<'i>(
        &self,
        operand: Expression,
        operator: PestPair<'i>,
    ) -> Result<Expression, ParseError> {
        let operator_span = operator.as_span().into();
        let mut pairs = operator.into_inner();
        Ok(Expression::Access(AccessExpression {
            span: operand.span().join(&operator_span),
            object: operand.into(),
            key: take!(self, pairs, expression, parse_expression)?.into(),
        }))
    }

    fn parse_pattern<'i>(&self, pair: PestPair<'i>) -> Result<Pattern, ParseError> {
        let span = pair.as_span().into();
        let pair = pair.into_inner().next().unwrap();
        match pair.as_rule() {
            Rule::map_pattern => self.parse_map_pattern(pair),
            Rule::list_pattern => self.parse_list_pattern(pair),
            Rule::wildcard => Ok(Pattern::Wildcard(span)),
            Rule::identifier => self.parse_identifier(pair).map(Pattern::Identifier),
            _ => unreachable!(),
        }
    }

    fn parse_map_pattern<'i>(&self, pair: PestPair<'i>) -> Result<Pattern, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner().peekable();
        let pairs = take_while!(self, pairs, map_pattern_pair, parse_map_pattern_pair)?;
        Ok(Pattern::Map(MapPattern { span, pairs }))
    }

    fn parse_map_pattern_pair<'i>(&self, pair: PestPair<'i>) -> Result<MapPatternPair, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        let key = take!(self, pairs, identifier, parse_identifier)?;
        let value = take_if!(self, pairs, pattern, parse_pattern)?;
        Ok(MapPatternPair { span, key, value })
    }

    fn parse_list_pattern<'i>(&self, pair: PestPair<'i>) -> Result<Pattern, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner();
        let items = take_while!(self, pairs, pattern, parse_pattern)?;
        Ok(Pattern::List(ListPattern { span, items }))
    }

    fn parse_identifier<'i>(&self, pair: PestPair<'i>) -> Result<Identifier, ParseError> {
        Ok(Identifier {
            span: pair.as_span().into(),
            identifier: pair.as_str().to_string(),
        })
    }

    fn parse_literal<'i>(&self, pair: PestPair<'i>) -> Result<Literal, ParseError> {
        let span = pair.as_span().into();
        let pair = pair.into_inner().next().unwrap();
        let literal = match pair.as_rule() {
            Rule::nil => Literal::Nil(span),
            Rule::bool => Literal::Bool(BoolLiteral {
                span,
                value: pair.as_str().parse().unwrap(),
            }),
            Rule::int => Literal::Int(IntLiteral {
                span,
                value: pair.as_str().parse().unwrap(),
            }),
            Rule::float => Literal::Float(FloatLiteral {
                span,
                value: pair.as_str().parse().unwrap(),
            }),
            _ => unreachable!(),
        };
        Ok(literal)
    }
}

#[derive(Parser)]
#[grammar = "src/grammar.pest"]
struct PestParser;

type PestError = pest::error::Error<Rule>;

type PestPairs<'i> = Pairs<'i, Rule>;
type PestPair<'i> = Pair<'i, Rule>;

static PRATT_PARSER: Lazy<PrattParser<Rule>> = Lazy::new(|| {
    PrattParser::new()
        .op(Op::infix(Rule::or, Assoc::Left))
        .op(Op::infix(Rule::and, Assoc::Left))
        .op(Op::infix(Rule::bit_or, Assoc::Left))
        .op(Op::infix(Rule::bit_xor, Assoc::Left))
        .op(Op::infix(Rule::bit_and, Assoc::Left))
        .op(Op::infix(Rule::eq, Assoc::Left) | Op::infix(Rule::neq, Assoc::Left))
        .op(Op::infix(Rule::gt, Assoc::Left)
            | Op::infix(Rule::gte, Assoc::Left)
            | Op::infix(Rule::lt, Assoc::Left)
            | Op::infix(Rule::lte, Assoc::Left))
        .op(Op::infix(Rule::shl, Assoc::Left) | Op::infix(Rule::shr, Assoc::Left))
        .op(Op::infix(Rule::add, Assoc::Left) | Op::infix(Rule::sub, Assoc::Left))
        .op(Op::infix(Rule::mul, Assoc::Left)
            | Op::infix(Rule::div, Assoc::Left)
            | Op::infix(Rule::rem, Assoc::Left))
        .op(Op::prefix(Rule::neg) | Op::prefix(Rule::not))
        .op(Op::postfix(Rule::call_expression_postfix))
        .op(Op::postfix(Rule::member_expression_postfix))
        .op(Op::postfix(Rule::access_expression_postfix))
});

#[cfg(test)]
mod tests {
    use crate::ast::{
        BinaryExpression, BinaryOperator, Block, Expression, FnExpression, Identifier, IntLiteral,
        LetStatement, Literal, MapExpression, MapExpressionKey, MapExpressionPair, Module, Pattern,
        Span, Statement,
    };

    use super::Parser;

    #[test]
    fn parse_module() {
        let source = "
            let x = 1;
            let y = 2;
            x + y
        ";
        let parser = Parser {};
        let module = parser.parse(source).unwrap();
        assert_eq!(
            module,
            Module {
                block: Block {
                    span: Span { start: 0, end: 73 },
                    statements: [
                        Statement::Let(LetStatement {
                            span: Span { start: 13, end: 23 },
                            pattern: Box::new(Pattern::Identifier(Identifier {
                                span: Span { start: 17, end: 18 },
                                identifier: "x".to_string(),
                            })),
                            value: Box::new(Expression::Literal(Literal::Int(IntLiteral {
                                span: Span { start: 21, end: 22 },
                                value: 1
                            }))),
                        }),
                        Statement::Let(LetStatement {
                            span: Span { start: 36, end: 46 },
                            pattern: Box::new(Pattern::Identifier(Identifier {
                                span: Span { start: 40, end: 41 },
                                identifier: "y".to_string(),
                            })),
                            value: Box::new(Expression::Literal(Literal::Int(IntLiteral {
                                span: Span { start: 44, end: 45 },
                                value: 2
                            }))),
                        }),
                    ]
                    .into(),
                    return_expression: Some(Box::new(Expression::Binary(BinaryExpression {
                        span: Span { start: 59, end: 64 },
                        operator: BinaryOperator::Add,
                        left: Box::new(Expression::Identifier(Identifier {
                            span: Span { start: 59, end: 60 },
                            identifier: "x".to_string(),
                        })),
                        right: Box::new(Expression::Identifier(Identifier {
                            span: Span { start: 63, end: 64 },
                            identifier: "y".to_string(),
                        })),
                    }))),
                },
            }
        );
    }

    #[test]
    fn parse_fn_expression() {
        let source = "
            fn(x, y) { x, y };
            fn(x, y) x + y;
        ";
        let parser = Parser {};
        let module = parser.parse(source).unwrap();
        dbg!(&module);
        assert_eq!(
            module,
            Module {
                block: Block {
                    span: Span { start: 0, end: 68 },
                    statements: [
                        Statement::Expression(Expression::Fn(FnExpression {
                            span: Span { start: 13, end: 30 },
                            parameters: [
                                Pattern::Identifier(Identifier {
                                    span: Span { start: 16, end: 17 },
                                    identifier: "x".to_string(),
                                }),
                                Pattern::Identifier(Identifier {
                                    span: Span { start: 19, end: 20 },
                                    identifier: "y".to_string(),
                                }),
                            ]
                            .into(),
                            body: Box::new(Expression::Map(MapExpression {
                                span: Span { start: 22, end: 30 },
                                pairs: [
                                    MapExpressionPair {
                                        span: Span { start: 24, end: 25 },
                                        key: MapExpressionKey::Identifier(Identifier {
                                            span: Span { start: 24, end: 25 },
                                            identifier: "x".to_string(),
                                        }),
                                        value: Box::new(Expression::Identifier(Identifier {
                                            span: Span { start: 24, end: 25 },
                                            identifier: "y".to_string(),
                                        })),
                                    },
                                    MapExpressionPair {
                                        span: Span { start: 27, end: 29 },
                                        key: MapExpressionKey::Identifier(Identifier {
                                            span: Span { start: 27, end: 28 },
                                            identifier: "x".to_string(),
                                        }),
                                        value: Box::new(Expression::Identifier(Identifier {
                                            span: Span { start: 27, end: 28 },
                                            identifier: "y".to_string(),
                                        })),
                                    },
                                ]
                                .into(),
                            })),
                        })),
                        Statement::Expression(Expression::Fn(FnExpression {
                            span: Span { start: 44, end: 58 },
                            parameters: [
                                Pattern::Identifier(Identifier {
                                    span: Span { start: 47, end: 48 },
                                    identifier: "x".to_string(),
                                }),
                                Pattern::Identifier(Identifier {
                                    span: Span { start: 50, end: 51 },
                                    identifier: "y".to_string(),
                                }),
                            ]
                            .into(),
                            body: Box::new(Expression::Binary(BinaryExpression {
                                span: Span { start: 53, end: 58 },
                                operator: BinaryOperator::Add,
                                left: Box::new(Expression::Identifier(Identifier {
                                    span: Span { start: 53, end: 54 },
                                    identifier: "x".to_string(),
                                })),
                                right: Box::new(Expression::Identifier(Identifier {
                                    span: Span { start: 57, end: 58 },
                                    identifier: "y".to_string(),
                                })),
                            })),
                        })),
                    ]
                    .into(),
                    return_expression: None,
                },
            }
        );
    }
}
