use 5.010;
use strict;
use warnings;

use Test::More tests => 6;

use YAML;

use_ok 'Marpa::Easy';

my $grammar = q{

    expr    ::= '-'? digit+ ('.' digit+)?
    digit   ::= '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'

};

my $ebnf = Marpa::Easy->new({
    rules => $grammar,
    default_action => 'xml',
    ebnf => 1,
});

isa_ok $ebnf, 'Marpa::Easy';

my $numbers = [
    '1234',
    '-1234.423',
    '-1234',
    '1234.423',
];

use XML::Twig;

for my $number (@$numbers){
    my $xml = $ebnf->parse($number);

    # setup XML parse tree
    my $t = XML::Twig->new;
    $t->parse($xml);

    unless (is $t->root->text, $number, "number $number lexed and parsed with EBNF"){
        say $ebnf->show_parse_tree;
    }
}