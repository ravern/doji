#[derive(Debug, PartialEq)]
pub struct Module {
    pub block: Block,
}

#[derive(Debug, PartialEq)]
pub struct Block {
    pub span: Span,
    pub statements: Box<[Statement]>,
    pub return_expression: Option<Box<Expression>>,
}

#[derive(Debug, PartialEq)]
pub enum Statement {
    Let(LetStatement),
    For(ForStatement),
    While(WhileStatement),
    Return(ReturnStatement),
    Break(Span),
    Continue(Span),
    Expression(Expression),
}

#[derive(Debug, PartialEq)]
pub struct LetStatement {
    pub span: Span,
    pub pattern: Box<Pattern>,
    pub value: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub struct ForStatement {
    pub span: Span,
    pub pattern: Box<Pattern>,
    pub iterable: Box<Expression>,
    pub body: Block,
}

#[derive(Debug, PartialEq)]
pub struct WhileStatement {
    pub span: Span,
    pub condition: Box<Expression>,
    pub body: Block,
}

#[derive(Debug, PartialEq)]
pub struct ReturnStatement {
    pub span: Span,
    pub value: Option<Box<Expression>>,
}

#[derive(Debug, PartialEq)]
pub enum Expression {
    Binary(BinaryExpression),
    Unary(UnaryExpression),
    Call(CallExpression),
    Member(MemberExpression),
    Access(AccessExpression),
    If(IfExpression),
    Fn(FnExpression),
    Map(MapExpression),
    List(ListExpression),
    Block(Block),
    Identifier(Identifier),
    Literal(Literal),
}

impl Expression {
    pub fn span(&self) -> Span {
        match self {
            Expression::Binary(expr) => expr.span.clone(),
            Expression::Unary(expr) => expr.span.clone(),
            Expression::Call(expr) => expr.span.clone(),
            Expression::Member(expr) => expr.span.clone(),
            Expression::Access(expr) => expr.span.clone(),
            Expression::If(expr) => expr.span.clone(),
            Expression::Fn(expr) => expr.span.clone(),
            Expression::Map(expr) => expr.span.clone(),
            Expression::List(expr) => expr.span.clone(),
            Expression::Block(expr) => expr.span.clone(),
            Expression::Identifier(identifier) => identifier.span.clone(),
            Expression::Literal(literal) => literal.span(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub struct BinaryExpression {
    pub span: Span,
    pub operator: BinaryOperator,
    pub left: Box<Expression>,
    pub right: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub enum BinaryOperator {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Neq,
    Gt,
    Gte,
    Lt,
    Lte,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
}

#[derive(Debug, PartialEq)]
pub struct UnaryExpression {
    pub span: Span,
    pub operator: UnaryOperator,
    pub operand: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub enum UnaryOperator {
    Neg,
    Not,
    BitNot,
}

#[derive(Debug, PartialEq)]
pub struct CallExpression {
    pub span: Span,
    pub callee: Box<Expression>,
    pub arguments: Box<[Expression]>,
}

#[derive(Debug, PartialEq)]
pub struct MemberExpression {
    pub span: Span,
    pub object: Box<Expression>,
    pub member: Identifier,
}

#[derive(Debug, PartialEq)]
pub struct AccessExpression {
    pub span: Span,
    pub object: Box<Expression>,
    pub key: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub struct IfExpression {
    pub span: Span,
    pub condition: Box<Expression>,
    pub if_body: Block,
    pub else_ifs: Box<[IfElseIf]>,
    pub else_body: Option<Block>,
}

#[derive(Debug, PartialEq)]
pub struct IfElseIf {
    pub span: Span,
    pub condition: Box<Expression>,
    pub body: Block,
}

#[derive(Debug, PartialEq)]
pub struct FnExpression {
    pub span: Span,
    pub parameters: Box<[Pattern]>,
    pub body: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub struct MapExpression {
    pub span: Span,
    pub pairs: Box<[MapExpressionPair]>,
}

#[derive(Debug, PartialEq)]
pub struct MapExpressionPair {
    pub span: Span,
    pub key: MapExpressionKey,
    pub value: Box<Expression>,
}

#[derive(Debug, PartialEq)]
pub enum MapExpressionKey {
    Identifier(Identifier),
    Expression(Box<Expression>),
}

#[derive(Debug, PartialEq)]
pub struct ListExpression {
    pub span: Span,
    pub items: Box<[Expression]>,
}

#[derive(Debug, PartialEq)]
pub enum Pattern {
    Map(MapPattern),
    List(ListPattern),
    Wildcard(Span),
    Identifier(Identifier),
}

impl Pattern {
    pub fn span(&self) -> Span {
        match self {
            Pattern::Map(pattern) => pattern.span.clone(),
            Pattern::List(pattern) => pattern.span.clone(),
            Pattern::Wildcard(span) => span.clone(),
            Pattern::Identifier(identifier) => identifier.span.clone(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub struct MapPattern {
    pub span: Span,
    pub pairs: Box<[MapPatternPair]>,
}

#[derive(Debug, PartialEq)]
pub struct MapPatternPair {
    pub span: Span,
    pub key: Identifier,
    pub value: Option<Pattern>,
}

#[derive(Debug, PartialEq)]
pub struct ListPattern {
    pub span: Span,
    pub items: Box<[Pattern]>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Identifier {
    pub span: Span,
    pub identifier: String,
}

#[derive(Debug, PartialEq)]
pub enum Literal {
    Nil(Span),
    Bool(BoolLiteral),
    Int(IntLiteral),
    Float(FloatLiteral),
}

impl Literal {
    pub fn span(&self) -> Span {
        match self {
            Literal::Nil(span) => span.clone(),
            Literal::Bool(literal) => literal.span.clone(),
            Literal::Int(literal) => literal.span.clone(),
            Literal::Float(literal) => literal.span.clone(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub struct BoolLiteral {
    pub span: Span,
    pub value: bool,
}

#[derive(Debug, PartialEq)]
pub struct IntLiteral {
    pub span: Span,
    pub value: u32,
}

#[derive(Debug, PartialEq)]
pub struct FloatLiteral {
    pub span: Span,
    pub value: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn combine(&self, other: &Span) -> Span {
        Span {
            start: self.start.min(other.start),
            end: self.end.max(other.end),
        }
    }
}

impl<'i> From<pest::Span<'i>> for Span {
    fn from(span: pest::Span<'i>) -> Self {
        Span {
            start: span.start(),
            end: span.end(),
        }
    }
}
