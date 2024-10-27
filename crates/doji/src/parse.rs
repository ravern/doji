use once_cell::sync::Lazy;
use pest::{
    iterators::{Pair, Pairs},
    pratt_parser::{Assoc, Op, PrattParser},
    Parser as _,
};
use pest_derive::Parser;

use crate::ast::{
    AccessExpression, BinaryExpression, BinaryOperator, Block, BoolLiteral, CallExpression,
    Expression, FloatLiteral, FnExpression, ForStatement, Identifier, IfElseIf, IfExpression,
    IfExpressionSemi, IntLiteral, LetStatement, ListExpression, ListPattern, Literal,
    MapExpression, MapExpressionKey, MapExpressionPair, MapPattern, MapPatternPair,
    MemberExpression, Module, Pattern, ReturnStatement, Span, Statement, UnaryExpression,
    UnaryOperator, WhileStatement,
};

#[derive(Debug)]
pub struct ParseError {
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

pub struct Parser {}

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
        let mut statements: Vec<Statement> = take_while!(self, pairs, statement, parse_statement)?;
        let mut return_expression =
            take_if!(self, pairs, expression, parse_expression)?.map(Box::new);
        if return_expression.is_none() {
            if let Some(statement) = statements.last() {
                if let Statement::IfExpressionSemi(if_expression_semi) = statement {
                    if !if_expression_semi.has_semi {
                        let if_expression_semi = match statements.pop().unwrap() {
                            Statement::IfExpressionSemi(if_expression_semi) => if_expression_semi,
                            _ => unreachable!(),
                        };
                        return_expression =
                            Some(Box::new(Expression::If(if_expression_semi.expression)));
                    }
                }
            }
        }
        Ok(Block {
            span,
            statements: statements.into(),
            return_expression,
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
            Rule::if_expression_semi => self.parse_if_expression_semi(pair),
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

    fn parse_if_expression_semi<'i>(&self, pair: PestPair<'i>) -> Result<Statement, ParseError> {
        let span = pair.as_span().into();
        let mut pairs = pair.into_inner().peekable();
        Ok(Statement::IfExpressionSemi(IfExpressionSemi {
            span,
            expression: match take!(self, pairs, if_expression, parse_if_expression)? {
                Expression::If(if_expression) => if_expression,
                _ => unreachable!(),
            },
            has_semi: pairs.next().is_some(),
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
            span: operator_span.combine(&operand.span()),
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
            span: left.span().combine(&right.span()),
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
            span: operand.span().combine(&operator_span),
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
            span: operand.span().combine(&operator_span),
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
            span: operand.span().combine(&operator_span),
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
    use pretty_assertions::assert_eq;

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
                                            identifier: "x".to_string(),
                                        })),
                                    },
                                    MapExpressionPair {
                                        span: Span { start: 27, end: 29 },
                                        key: MapExpressionKey::Identifier(Identifier {
                                            span: Span { start: 27, end: 28 },
                                            identifier: "y".to_string(),
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
