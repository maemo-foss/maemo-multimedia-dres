/******************************************************************************/
/*  This file is part of dres the resource policy dependency resolver.        */
/*                                                                            */
/*  Copyright (C) 2010 Nokia Corporation.                                     */
/*                                                                            */
/*  This library is free software; you can redistribute                       */
/*  it and/or modify it under the terms of the GNU Lesser General Public      */
/*  License as published by the Free Software Foundation                      */
/*  version 2.1 of the License.                                               */
/*                                                                            */
/*  This library is distributed in the hope that it will be useful,           */
/*  but WITHOUT ANY WARRANTY; without even the implied warranty of            */
/*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU          */
/*  Lesser General Public License for more details.                           */
/*                                                                            */
/*  You should have received a copy of the GNU Lesser General Public          */
/*  License along with this library; if not, write to the Free Software       */
/*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  */
/*  USA.                                                                      */
/******************************************************************************/

%{

#include <stdio.h>
#include <string.h>
#include <errno.h>

#include <glib-object.h>

#include "dres/dres.h"
#include "parser-types.h"


#if !defined(DEBUG) || defined(__TEST_PARSER__) || 1
#  define DEBUG(fmt, args...) printf("[parser] "fmt"\n", ## args)
#else
#  define DEBUG(fmt, args...)
#endif

#define FQFN(name) (factname(name))

/* parser/lexer interface */
int  yylex  (void);
void yyerror(dres_t *dres, char const *);
extern char *lexer_file(void);
extern int   lexer_line(void);
extern char *lexer_printable_token(const char *token);

extern FILE *yyin;

/* fact prefix support */
int   set_prefix(char *);
char *factname  (char *);

static char *current_prefix;



%}



%union {
    int              id;
    token_string_t   any;
    token_integer_t  integer;
    token_double_t   dbl;
    token_string_t   string;
    dres_target_t   *target;
    dres_prereq_t   *prereq;
    dres_varref_t    varref;
    dres_arg_t      *arg;
    dres_local_t    *local;
    dres_field_t     field;
    dres_select_t   *select;

    dres_init_t        *init;
    dres_initializer_t *initializer;

    dres_stmt_t        *statement;
    dres_expr_t        *expression;
    dres_op_t           dresop;
}

%defines
%parse-param {dres_t *dres}

%token <string>  TOKEN_PREFIX
%token <string>  TOKEN_IDENT
%token <string>  TOKEN_FACTNAME
%token           TOKEN_DOT "."
%token <string>  TOKEN_STRING
%token <integer> TOKEN_INTEGER
%token <dbl>     TOKEN_DOUBLE
%token <string>  TOKEN_FACTVAR
%token <string>  TOKEN_DRESVAR
%token           TOKEN_VARIABLES
%token           TOKEN_COLON ":"
%token           TOKEN_PAREN_OPEN  "("
%token           TOKEN_PAREN_CLOSE ")"
%token           TOKEN_CURLY_OPEN  "{"
%token           TOKEN_CURLY_CLOSE "}"
%token           TOKEN_BRACE_OPEN  "["
%token           TOKEN_BRACE_CLOSE "]"
%token           TOKEN_COMMA ","
%token           TOKEN_EQUAL   "="
%token           TOKEN_APPEND  "+="
%token           TOKEN_PARTIAL "|="
%token           TOKEN_REPLACE "*="
%token           TOKEN_TAB "\t"
%token           TOKEN_EOL
%token           TOKEN_EOF

%token           TOKEN_IF   "if"
%token           TOKEN_THEN "then"
%token           TOKEN_ELSE "else"
%token           TOKEN_END  "end"

%token           TOKEN_EQ   "=="
%token           TOKEN_NE   "!="
%token           TOKEN_LT   "<"
%token           TOKEN_LE   "<="
%token           TOKEN_GT   ">"
%token           TOKEN_GE   ">="
%token           TOKEN_NOT  "!"
%token           TOKEN_OR   "||"
%token           TOKEN_AND  "&&"

%left TOKEN_OR TOKEN_AND
%left TOKEN_EQ TOKEN_NE TOKEN_LT TOKEN_GT TOKEN_LE TOKEN_GE
%nonassoc TOKEN_NOT

%token           TOKEN_UNKNOWN
%token           TOKEN_LEXER_ERROR

%type <target>  rule
%type <id>      prereq
%type <prereq>  prereqs
%type <prereq>  optional_prereqs
%type <varref>  varref
%type <field>     field
%type <init>      ifields
%type <select>    sfields
%type <select>    sfield
%type <initializer> initializer
%type <local>       local
%type <local>       locals

%type <statement>   optional_statements
%type <statement>   statements
%type <statement>   statement
%type <statement>   stmt_ifthen
%type <statement>   stmt_assign
%type <statement>   stmt_call
%type <expression>  expr
%type <expression>  expr_const
%type <expression>  expr_varref
%type <expression>  expr_relop
%type <expression>  expr_call
%type <expression>  args_by_value
%type <dresop>      select_op

%%


input: optional_facts optional_local_decls rules

optional_facts: /* empty */
    | facts
    ;

facts: fact
    |  facts fact
    |  facts error {
           DRES_ERROR("failed to parse fact near token '%s' on line %d",
	              lexer_printable_token(yylval.any.token),
		      yylval.any.lineno);
           YYABORT;
    }
    ;

fact: prefix
    | initializer {
            dres_initializer_t *init;
	    if (dres->initializers != NULL) {
                for (init = dres->initializers; init->next; init = init->next)
                    ;
                init->next = $1;
            }
            else
                dres->initializers = $1;
    }
    ;

prefix: TOKEN_PREFIX "=" TOKEN_FACTNAME TOKEN_EOL {
            set_prefix($3.value);
        }
	| TOKEN_PREFIX "=" TOKEN_IDENT TOKEN_EOL {
            set_prefix($3.value);
	}
        ;


initializer: TOKEN_FACTVAR assign_op "{" ifields "}" TOKEN_EOL {
            dres_initializer_t *init;
            
            if ((init = ALLOC(dres_initializer_t)) == NULL)
	        YYABORT;
            init->variable = dres_factvar_id(dres, FQFN($1.value));
            init->fields   = $4;
            init->next     = NULL;

            $$ = init;
        }
        ;

assign_op: "=" | "+=";

ifields: field {
            if (($$ = ALLOC(dres_init_t)) == NULL)
	        YYABORT;
            $$->field = $1;
            $$->next  = NULL;
        }
        | ifields "," field {
            dres_init_t *f, *p;
            if ((f = ALLOC(dres_init_t)) == NULL)
                YYABORT;
            for (p = $1; p->next; p = p->next)
                ;
	    p->next  = f;
            f->field = $3;
            f->next  = NULL;
            $$       = $1;
        }
        | ifields error  {
            DRES_ERROR("failed to parse fact initializer token '%s' on line %d",
	               lexer_printable_token(yylval.any.token),
		       yylval.any.lineno);
           YYABORT;
        }
        ;

optional_local_decls: /* empty */
        | local_decls
        ;

local_decls: local_decl
        | local_decls local_decl
        ;

local_decl: TOKEN_VARIABLES dresvars TOKEN_EOL
        ;

dresvars: dresvar
        | dresvars "," dresvar
        | dresvars error {
              DRES_ERROR("failed to parse local declaration near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
           YYABORT;
        }
        ;

dresvar: TOKEN_DRESVAR { dres_dresvar_id(dres, $1.value); }
      |  TOKEN_IDENT   { dres_dresvar_id(dres, $1.value); }
      ;

sfields: sfield { $$ = $1; }
        | sfields "," sfield {
	    dres_select_t *p;
            for (p = $1; p->next; p = p->next)
                ;
	    p->next = $3;
            $$      = $1;
        }
        | sfields error {
              DRES_ERROR("failed to parse selectors near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
              YYABORT;
        }
        ;


sfield: TOKEN_IDENT select_op TOKEN_INTEGER {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
            $$->field.name = STRDUP($1.value);
            $$->field.value.type = DRES_TYPE_INTEGER;
	    $$->field.value.v.i  = $3.value;
        }
	| TOKEN_INTEGER select_op TOKEN_INTEGER {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
            $$->field.value.type = DRES_TYPE_INTEGER;
	    $$->field.value.v.i  = $3.value;
        }
        | TOKEN_IDENT select_op TOKEN_DOUBLE {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
            $$->field.name = STRDUP($1.value);
            $$->field.value.type = DRES_TYPE_DOUBLE;
	    $$->field.value.v.d  = $3.value;
        }
        | TOKEN_INTEGER select_op TOKEN_DOUBLE {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
            $$->field.value.type = DRES_TYPE_DOUBLE;
	    $$->field.value.v.d  = $3.value;
        }
        | TOKEN_IDENT select_op TOKEN_STRING {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
            $$->field.name = STRDUP($1.value);
            $$->field.value.type = DRES_TYPE_STRING;
            $$->field.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_INTEGER select_op TOKEN_STRING {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
            $$->field.value.type = DRES_TYPE_STRING;
            $$->field.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_IDENT select_op TOKEN_IDENT {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
            $$->field.name = STRDUP($1.value);
            $$->field.value.type = DRES_TYPE_STRING;
            $$->field.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_INTEGER select_op TOKEN_IDENT {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
            $$->field.value.type = DRES_TYPE_STRING;
            $$->field.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_IDENT select_op TOKEN_DRESVAR {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
            $$->field.name = STRDUP($1.value);
            $$->field.value.type = DRES_TYPE_DRESVAR;
            $$->field.value.v.id = dres_dresvar_id(dres, $3.value);
        }
        | TOKEN_INTEGER select_op TOKEN_DRESVAR {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = $2;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
            $$->field.value.type = DRES_TYPE_DRESVAR;
            $$->field.value.v.id = dres_dresvar_id(dres, $3.value);
        }
	| TOKEN_IDENT {
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = DRES_OP_UNKNOWN;
            $$->field.name = STRDUP($1.value);
	    $$->field.value.type = DRES_TYPE_UNKNOWN;
	    $$->field.value.v.i  = 0;
	}
	| TOKEN_INTEGER {
	    char field[64];
	    if (($$ = ALLOC(dres_select_t)) == NULL)
	        YYABORT;
	    $$->op = DRES_OP_UNKNOWN;
	    snprintf(field, sizeof(field), "%d", $1.value);
            $$->field.name = STRDUP(field);
	    $$->field.value.type = DRES_TYPE_UNKNOWN;
	    $$->field.value.v.i  = 0;
	}
        ;

select_op: ":" "!" { $$ = DRES_OP_NEQ; }
        |  ":"     { $$ = DRES_OP_EQ;  }
        ;

field: TOKEN_IDENT ":" TOKEN_INTEGER {
            $$.name = STRDUP($1.value);
            $$.value.type = DRES_TYPE_INTEGER;
	    $$.value.v.i  = $3.value;
        }
        | TOKEN_INTEGER ":" TOKEN_INTEGER {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
            $$.value.type = DRES_TYPE_INTEGER;
	    $$.value.v.i  = $3.value;
        }
        | TOKEN_IDENT ":" TOKEN_DOUBLE {
            $$.name = STRDUP($1.value);
            $$.value.type = DRES_TYPE_DOUBLE;
	    $$.value.v.d  = $3.value;
        }
        | TOKEN_INTEGER ":" TOKEN_DOUBLE {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
            $$.value.type = DRES_TYPE_DOUBLE;
	    $$.value.v.d  = $3.value;
        }
        | TOKEN_IDENT ":" TOKEN_STRING {
            $$.name = STRDUP($1.value);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_INTEGER ":" TOKEN_STRING {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_IDENT ":" TOKEN_IDENT {
            $$.name = STRDUP($1.value);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_INTEGER ":" TOKEN_IDENT {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP($3.value);
        }
        | TOKEN_IDENT ":" {
            $$.name = STRDUP($1.value);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP("");
        }
        | TOKEN_INTEGER ":" {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
            $$.value.type = DRES_TYPE_STRING;
            $$.value.v.s  = STRDUP("");
        }
	| TOKEN_IDENT {
	    $$.name = STRDUP($1.value);
	    $$.value.type = DRES_TYPE_UNKNOWN;
	    $$.value.v.i  = 0;
	}
	| TOKEN_INTEGER {
	    char field[64];
            snprintf(field, sizeof(field), "%d", $1.value);
            $$.name = STRDUP(field);
	    $$.value.type = DRES_TYPE_UNKNOWN;
	    $$.value.v.i  = 0;
	}
        ;

rules:    rule
	| rules rule
        | rules prefix
        | rules error {
              DRES_ERROR("failed to parse rule or prefix near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
              YYABORT;
        }
	;


rule: TOKEN_IDENT ":" optional_prereqs TOKEN_EOL optional_statements {
            dres_target_t *t = dres_lookup_target(dres, $1.value);

            if (!DRES_IS_DEFINED(t->id)) {
                t->prereqs    = $3;
                t->statements = $5;
                t->id         = DRES_DEFINED(t->id);
            }
            else {
                dres_stmt_t *s;
                int          i;

                /* append prerequisits */
                if (t->prereqs != NULL) {
                    if ($3 != NULL) {
                        for (i = 0; i < $3->nid; i++) {
                            if (dres_add_prereq(t->prereqs, $3->ids[i]) != 0)
                                YYABORT;
                        }
                        
                        dres_free_prereq($3);
                    }
                }
                else
                    t->prereqs = $3;

                /* append statements */
                if (t->statements != NULL) {
                    for (s = t->statements; s->any.next; s = s->any.next)
                        ;
                    s->any.next = $5;
                }
                else
                    t->statements = $5;
            }

            $$ = t;
        }
	;

optional_prereqs: /* empty */    { $$ = NULL; }
	| prereqs                { $$ = $1;   }
	;

prereqs:  prereq                 { $$ = dres_new_prereq($1);          }
	| prereqs prereq         { dres_add_prereq($1, $2); $$ = $1;  }
        | prereqs error {
              DRES_ERROR("failed to parse target prerequisits near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
              YYABORT;
        }
	;

prereq:   TOKEN_IDENT            { $$ = dres_target_id(dres, $1.value); }
	| TOKEN_FACTVAR          {
            dres_variable_t *v;
            $$ = dres_factvar_id(dres, FQFN($1.value));
            if ((v = dres_lookup_variable(dres, $$)) != NULL)
                v->flags |= DRES_VAR_PREREQ;
        }
	;

varref: TOKEN_FACTVAR {
            $$.variable = dres_factvar_id(dres, FQFN($1.value));
            $$.selector = NULL;
            $$.field    = NULL;
        }
        | TOKEN_FACTVAR ":" TOKEN_IDENT {
            $$.variable = dres_factvar_id(dres, FQFN($1.value));
            $$.selector = NULL;
            $$.field    = STRDUP($3.value);
        }
        | TOKEN_FACTVAR ":" TOKEN_INTEGER {
	    char field[64];
            $$.variable = dres_factvar_id(dres, FQFN($1.value));
            $$.selector = NULL;
	    snprintf(field, sizeof(field), "%d", $3.value);
            $$.field    = STRDUP(field);
        }
        | TOKEN_FACTVAR "[" sfields "]" {
            $$.variable = dres_factvar_id(dres, FQFN($1.value));
            $$.selector = $3;
            $$.field    = NULL;
        }
        | TOKEN_FACTVAR "[" sfields "]" ":" TOKEN_IDENT {
            $$.variable = dres_factvar_id(dres, FQFN($1.value));
            $$.selector = $3;
            $$.field    = STRDUP($6.value);
        }
        ;



locals:   local { $$ = $1; }
        | locals "," local {
            dres_local_t *l;

            for (l = $1; l->next != NULL; l = l->next)
                ;
            l->next = $3;
            $$ = $1;
        }
        | locals error {
              DRES_ERROR("failed to parse local arguments near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
              YYABORT;
        }


local:    TOKEN_DRESVAR "=" TOKEN_INTEGER {
            if (($$ = ALLOC(dres_local_t)) == NULL)
                YYABORT;
            $$->id         = dres_dresvar_id(dres, $1.value);
            $$->value.type = DRES_TYPE_INTEGER;
            $$->value.v.i  = $3.value;
            $$->next       = NULL;
             
        }
        | TOKEN_DRESVAR "=" TOKEN_DOUBLE {
            if (($$ = ALLOC(dres_local_t)) == NULL)
                YYABORT;
            $$->id         = dres_dresvar_id(dres, $1.value);
            $$->value.type = DRES_TYPE_DOUBLE;
            $$->value.v.d  = $3.value;
            $$->next       = NULL;

            if ($$->id == DRES_ID_NONE)
                YYABORT;
        }
        | TOKEN_DRESVAR "=" TOKEN_STRING {
            if (($$ = ALLOC(dres_local_t)) == NULL)
                YYABORT;
            $$->id         = dres_dresvar_id(dres, $1.value);
            $$->value.type = DRES_TYPE_STRING;
            $$->value.v.s  = STRDUP($3.value);
            $$->next       = NULL;
             
            if ($$->id == DRES_ID_NONE)
                YYABORT;
        }
        | TOKEN_DRESVAR "=" TOKEN_IDENT {
            if (($$ = ALLOC(dres_local_t)) == NULL)
                YYABORT;
            $$->id         = dres_dresvar_id(dres, $1.value);
            $$->value.type = DRES_TYPE_STRING;
            $$->value.v.s  = STRDUP($3.value);
            $$->next       = NULL;             

            if ($$->id == DRES_ID_NONE)
                YYABORT;
        }
        | TOKEN_DRESVAR "=" TOKEN_DRESVAR {
            if (($$ = ALLOC(dres_local_t)) == NULL)
                YYABORT;
            $$->id         = dres_dresvar_id(dres, $1.value);
            $$->value.type = DRES_TYPE_DRESVAR;
            $$->value.v.id = dres_dresvar_id(dres, $3.value);
            $$->next       = NULL;             

            if ($$->id == DRES_ID_NONE || $$->value.v.id == DRES_ID_NONE)
                YYABORT;
        }
        ;



optional_statements: /* empty */ { $$ = NULL; }
	| statements             { $$ = $1;   }
	;

statements: statement            { $$ = $1; }
	|   statements statement {
            dres_stmt_t *s;

            for (s = $1; s->any.next; s = s->any.next)
                ;

            s->any.next = $2;
            $$          = $1;
        }
        |   statements error {
              DRES_ERROR("failed to parse statements near token '%s' "
                         "on line %d", lexer_printable_token(yylval.any.token),
			 yylval.any.lineno);
              YYABORT;
        }
	;

statement: TOKEN_TAB stmt_ifthen TOKEN_EOL { $$ = $2; }
        |  TOKEN_TAB stmt_assign TOKEN_EOL { $$ = $2; }
        |  TOKEN_TAB stmt_call   TOKEN_EOL { $$ = $2; }
        ;


stmt_ifthen: TOKEN_IF expr TOKEN_THEN TOKEN_EOL 
                      statements TOKEN_TAB TOKEN_END {
             dres_stmt_if_t *stmt = ALLOC(typeof(*stmt));
             if (stmt == NULL)
                 YYABORT;

             stmt->type        = DRES_STMT_IFTHEN;
             stmt->condition   = $2;
             stmt->if_branch   = $5;
             stmt->else_branch = NULL;

             $$ = (dres_stmt_t *)stmt;
        }
        | TOKEN_IF expr TOKEN_THEN TOKEN_EOL 
                   statements TOKEN_TAB TOKEN_ELSE TOKEN_EOL 
                   statements TOKEN_TAB TOKEN_END {
             dres_stmt_if_t *stmt = ALLOC(typeof(*stmt));
             if (stmt == NULL)
                 YYABORT;

             stmt->type        = DRES_STMT_IFTHEN;
             stmt->condition   = $2;
             stmt->if_branch   = $5;
             stmt->else_branch = $9;

             $$ = (dres_stmt_t *)stmt;
        }
        ;

stmt_assign: varref "=" expr {
            dres_stmt_assign_t *a;
            dres_expr_varref_t *vr;

            if ((a = ALLOC(typeof(*a))) == NULL)
                YYABORT;

            if ((vr = ALLOC(typeof(*vr))) == NULL) {
	        dres_free_statement((dres_stmt_t *)a);
		YYABORT;
            }

	    vr->type = DRES_EXPR_VARREF;
            vr->ref  = $1;

            a->type   = DRES_STMT_FULL_ASSIGN;
	    a->lvalue = vr;
            a->rvalue = $3;

            $$ = (dres_stmt_t *)a;
        }
        |   varref "|=" expr {
            dres_stmt_assign_t *a;
            dres_expr_varref_t *vr;

            if ((a = ALLOC(typeof(*a))) == NULL)
                YYABORT;

	    if ((vr = ALLOC(typeof(*vr))) == NULL) {
	        dres_free_statement((dres_stmt_t *)a);
		YYABORT;
            }

	    vr->type = DRES_EXPR_VARREF;
            vr->ref  = $1;

            a->type   = DRES_STMT_PARTIAL_ASSIGN;
	    a->lvalue = vr;
            a->rvalue = $3;

            $$ = (dres_stmt_t *)a;
        }
        |   varref "*=" expr {
            dres_stmt_assign_t *a;
            dres_expr_varref_t *vr;

            if ((a = ALLOC(typeof(*a))) == NULL)
                YYABORT;

	    if ((vr = ALLOC(typeof(*vr))) == NULL) {
	        dres_free_statement((dres_stmt_t *)a);
		YYABORT;
            }

	    vr->type = DRES_EXPR_VARREF;
            vr->ref  = $1;

            a->type   = DRES_STMT_REPLACE_ASSIGN;
	    a->lvalue = vr;
            a->rvalue = $3;

            $$ = (dres_stmt_t *)a;
        }
        ;

stmt_call: TOKEN_IDENT "(" args_by_value "," locals ")" {
            dres_stmt_call_t *call = ALLOC(typeof(*call));
            int               status;

            if (call == NULL)
                YYABORT;

            call->type   = DRES_STMT_CALL;
            call->name   = STRDUP($1.value);
            call->args   = $3;
	    call->locals = $5;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_statement((dres_stmt_t *)call);
	        YYABORT;
            }

            $$ = (dres_stmt_t *)call;
        }
        | TOKEN_IDENT "(" args_by_value ")" {
            dres_stmt_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type   = DRES_STMT_CALL;
            call->name   = STRDUP($1.value);
            call->args   = $3;
	    call->locals = NULL;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_statement((dres_stmt_t *)call);
	        YYABORT;
            }

            $$ = (dres_stmt_t *)call;
        }
        | TOKEN_IDENT "(" locals ")" {
            dres_stmt_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type   = DRES_STMT_CALL;
            call->name   = STRDUP($1.value);
            call->args   = NULL;
	    call->locals = $3;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_statement((dres_stmt_t *)call);
	        YYABORT;
            }

            $$ = (dres_stmt_t *)call;
        }
	| TOKEN_IDENT "(" ")" {
            dres_stmt_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type   = DRES_STMT_CALL;
            call->name   = STRDUP($1.value);
            call->args   = NULL;
	    call->locals = NULL;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_statement((dres_stmt_t *)call);
	        YYABORT;
            }

            $$ = (dres_stmt_t *)call;
        }

args_by_value: expr { $$ = $1; }
     | args_by_value "," expr {
         dres_expr_t *arg;

         for (arg = $1; arg->any.next; arg = arg->any.next)
             ;

         arg->any.next = $3;
         $$ = $1;
     }
     | args_by_value error {
           DRES_ERROR("failed to parse arguments near token '%s' "
                      "on line %d", lexer_printable_token(yylval.any.token),
		      yylval.any.lineno);
           YYABORT;
     }
     ;


expr:  expr_const   { $$ = $1; }
     | expr_varref  { $$ = $1; }
     | expr_relop   { $$ = $1; }
     | expr_call    { $$ = $1; }
     | "(" expr ")" { $$ = $2; }
     | error {
           DRES_ERROR("failed to parse expression near token '%s' "
                      "on line %d", lexer_printable_token(yylval.any.token),
		      yylval.any.lineno);
           YYABORT;
     }
     ;

expr_const: TOKEN_INTEGER {
                dres_expr_const_t *c = ALLOC(typeof(*c));

                if (c == NULL)
                    YYABORT;

                c->type  = DRES_EXPR_CONST;
		c->vtype = DRES_TYPE_INTEGER;
                c->v.i   = $1.value;

                $$ = (dres_expr_t *)c;
            }
            | TOKEN_DOUBLE {
                dres_expr_const_t *c = ALLOC(typeof(*c));

                if (c == NULL)
                    YYABORT;

                c->type  = DRES_EXPR_CONST;
		c->vtype = DRES_TYPE_DOUBLE;
                c->v.d   = $1.value;

                $$ = (dres_expr_t *)c;
            }
            | TOKEN_STRING {
                dres_expr_const_t *c = ALLOC(typeof(*c));

                if (c == NULL)
                    YYABORT;

                c->type  = DRES_EXPR_CONST;
		c->vtype = DRES_TYPE_STRING;
                c->v.s   = STRDUP($1.value);

                $$ = (dres_expr_t *)c;
            }
            | TOKEN_IDENT {
                dres_expr_const_t *c = ALLOC(typeof(*c));

                if (c == NULL)
                    YYABORT;

                c->type  = DRES_EXPR_CONST;
		c->vtype = DRES_TYPE_STRING;
                c->v.s   = STRDUP($1.value);

                $$ = (dres_expr_t *)c;
            }
            ;

expr_varref: varref {
                dres_expr_varref_t *vr = ALLOC(typeof(*vr));

                if (vr == NULL)
                    YYABORT;

                vr->type = DRES_EXPR_VARREF;
                vr->ref  = $1;

                $$ = (dres_expr_t *)vr;
            }
            | TOKEN_DRESVAR {
                dres_expr_varref_t *vr = ALLOC(typeof(*vr));

                if (vr == NULL)
                    YYABORT;

                vr->type         = DRES_EXPR_VARREF;
		vr->ref.variable = dres_dresvar_id(dres, $1.value);

                $$ = (dres_expr_t *)vr;
            }
            ;

expr_relop: expr "<" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_LT;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr "<=" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_LE;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr ">" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_GT;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr ">=" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_GE;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr "==" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_EQ;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr "!=" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_NE;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | "!" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_NOT;
                op->arg1 = $2;
                op->arg2 = NULL;

                $$ = (dres_expr_t *)op;
            }
            | expr "||" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_OR;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            | expr "&&" expr {
                dres_expr_relop_t *op = ALLOC(typeof(*op));

                if (op == NULL)
                    YYABORT;

                op->type = DRES_EXPR_RELOP;
                op->op   = DRES_RELOP_AND;
                op->arg1 = $1;
                op->arg2 = $3;

                $$ = (dres_expr_t *)op;
            }
            ;


expr_call: TOKEN_IDENT "(" args_by_value "," locals ")" {
            dres_expr_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type    = DRES_EXPR_CALL;
            call->name    = STRDUP($1.value);
            call->args    = $3;
	    call->locals  = $5;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_expr((dres_expr_t *)call);
	        YYABORT;
            }

            $$ = (dres_expr_t *)call;
        }
        | TOKEN_IDENT "(" args_by_value ")" {
            dres_expr_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type    = DRES_EXPR_CALL;
            call->name    = STRDUP($1.value);
            call->args    = $3;
	    call->locals  = NULL;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_expr((dres_expr_t *)call);
	        YYABORT;
            }

            $$ = (dres_expr_t *)call;
        }
        | TOKEN_IDENT "(" locals ")" {
            dres_expr_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type    = DRES_EXPR_CALL;
            call->name    = STRDUP($1.value);
            call->args    = NULL;
	    call->locals  = $3;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_expr((dres_expr_t *)call);
	        YYABORT;
            }

            $$ = (dres_expr_t *)call;
        }
	| TOKEN_IDENT "(" ")" {
            dres_expr_call_t *call = ALLOC(typeof(*call));
	    int               status;

            if (call == NULL)
                YYABORT;

            call->type    = DRES_EXPR_CALL;
            call->name    = STRDUP($1.value);
            call->args    = NULL;
	    call->locals  = NULL;

	    status = dres_register_handler(dres, call->name, NULL);
	    if (status != 0 && status != EEXIST) {
	        dres_free_expr((dres_expr_t *)call);
	        YYABORT;
            }

            $$ = (dres_expr_t *)call;
        }
	;


%%


/********************
 * set_prefix
 ********************/
int
set_prefix(char *prefix)
{
    if (current_prefix != NULL)
        FREE(current_prefix);
    current_prefix = STRDUP(prefix);
    
    return current_prefix == NULL ? ENOMEM : 0;
}

/********************
 * factname
 ********************/
char *
factname(char *name)
{
    static char  buf[256];
    char        *prefix = current_prefix;

    /*
     * Notes:
     *     Although notation-wise this is counterintuitive because of
     *     the overloaded use of '.' we do have filesystem pathname-like
     *     conventions here. Absolute variable names start with a dot,
     *     relative variable names do not. The leading dot is removed
     *     from absolute names. Relative names get prefixed with the
     *     current prefix if any.
     *
     *     The other and perhaps more intuitive alternative would be to
     *     have it the other way around and prefix any variable names
     *     starting with a dot with the current prefix.
     *
     *     Since the absolute/relative notation is backward-compatible
     *     with our original concept of a single default prefix we use
     *     that one.
     */

    if (name[0] != '.' && prefix && prefix[0]) {
        snprintf(buf, sizeof(buf), "%s.%s", prefix, name);
        name = buf;
    }
    else if (name[0] == '.')
        return name + 1;

    return name;
}


/********************
 * yyerror
 ********************/
void
yyerror(dres_t *dres, const char *msg)
{
    (void)dres;

    DRES_ERROR("parse error: %s near token '%s' on line %d in file %s",
               msg, lexer_printable_token(yylval.any.token),
	        lexer_line(), lexer_file());
}



#ifdef __TEST_PARSER__	

int main(int argc, char *argv[])
{
  yyin = argc > 1 ? fopen(argv[1], "r") : stdin;

  yyparse(NULL);
  
  return 0;

}

#endif /* __TEST_PARSER__ */


/* 
 * Local Variables:
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:set expandtab shiftwidth=4:
 */
