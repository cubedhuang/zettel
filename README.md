# Zettel

A simple scripting language.

```js
fn fib(n) {
  if n <= 1 {
    return n
  }
  return fib(n - 1) + fib(n - 2)
}
print("the 10th Fibonacci number is", fib(10))
```

Classes as namespaces.

```js
//! Vector.zettel
constructor init(self, x, y) {
  self.x = x
  self.y = y
}
fn add(a, b) {
  return init(a.x + b.x, a.y + b.y)
}
fn dot(a, b) {
  return a.x * b.x + a.y * b.y
}
UNIT_X := init(1, 0)

//! main.zettel
import "Vector.zettel"
a := Vector.init(1, 2)
b := Vector.init(2, 3)
a = a.add(b) // Vector(3, 5)
x := a.dot(Vector.UNIT_X) // 3
```

The above is identical to the following:

```js
class Vector {
  constructor init(self, x, y) {
    // ...
  }
  // ...
}

a := Vector.init(1, 2)
// ...
```

```js
import "zettel:http"
import "zettel:fs"
words := http.fetch("https://api.linku.la/words").json()
for word in words {
  file := fs.File.init(word.id + ".md")
  file.write("# " + word.id + "\n")
}
```

## Grammar

Newline tokens are only emitted when after a certain subset of tokens and not before a certain subset of tokens.

```peg
Root <- container_doc_comment? Stmt* EOF

Stmt <- Block
      / ImportDecl
      / FnDecl
      / ConstructorDecl
      / ClassDecl
      / ReturnStmt
      / BreakStmt
      / ContinueStmt
      / IfStmt
      / ForStmt
      / SimpleStmt
# EOF is not consumed
stmt_terminator
    <- NEWLINE
     / SEMICOLON
     / EOF

Block <- LBRACE Decl* RBRACE NEWLINE?

ImportDecl <- KEYWORD_import IDENTIFIER? STRINGLITERAL stmt_terminator

FnDecl <- KEYWORD_fn IDENTIFIER FnParams NEWLINE? Block
FnParams <- LPAREN FnParamsRest
FnParamsRest
    <- RPAREN
     / DOT3 COMMA? RPAREN
     / ParamDecl (COMMA FnParamsRest / RPAREN)

# Requires at least one parameter. May only be the direct child of a class block.
ConstructorDecl <- KEYWORD_constructor IDENTIFIER FnParams NEWLINE? Block

ClassDecl <- KEYWORD_class IDENTIFIER NEWLINE? Block

ReturnStmt <- KEYWORD_return Expr? stmt_terminator

BreakStmt <- KEYWORD_break IDENTIFIER? stmt_terminator

ContinueStmt <- KEYWORD_continue IDENTIFIER? stmt_terminator

IfStmt <- KEYWORD_if (InlineSimpleStmt SEMICOLON)? Expr NEWLINE? Block Else?
Else <- KEYWORD_else ElseRest
ElseRest <- IfStmt
          / Block

ForStmt <- ForSimple
         / ForFull

ForSimple <- KEYWORD_for Expr? NEWLINE? Block

# The second InlineSimpleStmt may not be a VarDecl
ForFull <- KEYWORD_for InlineSimpleStmt? SEMICOLON Expr? SEMICOLON InlineSimpleStmt NEWLINE? Block Else?

SimpleStmt <- InlineSimpleStmt stmt_terminator
InlineSimpleStmt
    <- VarDecl
     / AssignStmt
     / Expr
     
# later validated to be a list of identifiers
VarDecl <- ExprList COLON_EQUAL ExprList

# later validated to be a list of lvalues
AssignStmt <- ExprList AssignOp ExprList

ExprList <- Expr (COMMA Expr)*

Expr <- TernaryExpr
TernaryExpr <- BoolOrExpr (KEYWORD_if BoolOrExpr KEYWORD_else TernaryExpr)?
BoolOrExpr <- BoolAndExpr (OrOp BoolAndExpr)*
BoolAndExpr <- CompareExpr (AndOp CompareExpr)*
CompareExpr <- BitwiseExpr (CompareOp BitwiseExpr)?
BitwiseExpr <- BitShiftExpr (BitwiseOp BitShiftExpr)*
BitShiftExpr <- AdditionExpr (BitShiftOp AdditionExpr)*
AdditionExpr <- MultiplyExpr (AdditionOp MultiplyExpr)*
MultiplyExpr <- PrefixExpr (MultiplyOp PrefixExpr)*
PrefixExpr <- PrefixOp* PostfixExpr
PostfixExpr <- PrimaryExpr (Call / Member / Index)*

Call <- LPAREN ExprList? COMMA? RPAREN
Member <- DOT IDENTIFIER
Index <- LBRACK Expr RBRACK

PrimaryExpr
    <- FnExpr
     / ClassExpr
     / InitList
     / GroupedExpr
     / IDENTIFIER
     / COLON IDENTIFIER
     / NUMBERLITERAL
     / STRINGLITERAL
     / KEYWORD_true
     / KEYWORD_false
     / KEYWORD_nil

FnExpr <- KEYWORD_fn FnParams NEWLINE? Block
ClassExpr <- KEYWORD_class NEWLINE? Block
InitList <- LBRACK ExprList COMMA? RBRACK
GroupedExpr <- LPAREN Expr RPAREN
```
