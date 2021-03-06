use 5.010;
use strict;
use warnings;

use Test::More;

use YAML;

use_ok 'MarpaX::Parse';
use_ok 'MarpaX::Parse::Tree';

# every actionable symbol will be handled as array of arrays
# so that the same tests shall pas for both grammars

# this produces array of arrays with embedded actions (applying AoA default_action 
# to non-actionable symbols)
my $AoA_with_embedded_actions = q{

    expression  ::= 
        term  
        ( 
            ( 
                '+'
                %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} 
                |
                '-' 
                %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} 
            ) 
            term 
        )* 
    # this is the action of the last subexpression
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c  %}

# this is the action of <subexpression> rule
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
    term        ::= 
        factor  
        ( 
            ( 
                '*' 
                %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} |
                '/' 
                %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} )
            factor
        )* 
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
    factor      ::= 
        constant 
            %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        variable
            %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '('  expression  ')' 
            %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
    variable    ::= 
        'x' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} |
        'y' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} |
        'z' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
# digit+ cannot have a rule 
    constant    ::= 
        digit+
        
        ('.' digit+)? 
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
        
        %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}

    digit       ::= 
        '0' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '1' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '2' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '3' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '4' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '5' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '6' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '7' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '8' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} | 
        '9' %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %} 
    %{ shift; my @c = grep { defined } @_; @c > 1 ? \@c : shift @c %}
    
};

# this produces array of arrays with default actions
my $AoA_with_default_action = q{

    expression  ::= term  ( ( '+' | '-' ) term )* 
    term        ::= factor  ( ( '*' | '/' ) factor)*
    factor      ::= constant | variable | '('  expression  ')'
    variable    ::= 'x' | 'y' | 'z'
    constant    ::= digit+ ('.' digit+)?
    digit       ::= '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'
    
};

# set up no-actions grammar
my $ebnf = MarpaX::Parse->new({
    rules => $AoA_with_default_action,
    default_action => 'MarpaX::Parse::Tree::AoA',
    quantifier_rules => 'recursive',
    nullables_for_quantifiers => 1,
}) or die "Can't create grammar: $@";

isa_ok $ebnf, 'MarpaX::Parse';

my $tests = [

# numbers

    [   '1234.132',             
        "[['1','2','3','4'],['.',['1','3','2']]]" ],

    [   '-1234',                
        "['1','2','3','4']" ],

# actions

    [   '1234 + 4321',          
        "[['1','2','3','4'],[['+',['4','3','2','1']]]]" ],

    [   '(1234 + 1234) / 123',  
        "[['(',[['1','2','3','4'],[['+',['1','2','3','4']]]],')'],[['/',['1','2','3']]]]" ],

# variables

    [   'x + 1',                
        "['x',[['+',['1']]]]" ],

    [   '(x + 1) + 2',          
        "[['(',['x',[['+',['1']]]],')'],[['+',['2']]]]" ],

    [   '((x + 1)/4) + 2',      
        "[['(',[['(',['x',[['+',['1']]]],')'],[['/',['4']]]],')'],[['+',['2']]]]" ],

    [   '(x + y)/z + 2',          
        "[[['(',['x',[['+','y']]],')'],[['/','z']]],[['+',['2']]]]" ],
];

use Data::Dumper;
$Data::Dumper::Terse = 1;          # don't output names where feasible
$Data::Dumper::Indent = 0;         # turn off all pretty print

for my $test (@$tests){

    my ($expr, $expected) = @$test;

    my $value = $ebnf->parse($expr);

    unless (is Dumper($value), $expected, "expression $expr parsed with EBNF using AoA default action"){
#        say $ebnf->show_parse_tree;
        say Dumper $value;
    }

}

#
# set up grammar with descriving actions
#
$ebnf = MarpaX::Parse->new({
    rules => $AoA_with_embedded_actions,
    default_action => 'MarpaX::Parse::Tree::AoA',
    quantifier_rules => 'recursive',
    nullables_for_quantifiers => 1,
}) or die "Can't create grammar: $@";

isa_ok $ebnf, 'MarpaX::Parse';

for my $test (@$tests){

    my ($expr, $expected) = @$test;

    my $value = $ebnf->parse($expr);

    unless (is Dumper($value), $expected, "expression $expr parsed with EBNF having AoA actions embedded"){
#        say $ebnf->show_parse_tree;
        say Dumper $value;
    }

}

done_testing;
