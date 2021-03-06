use 5.010;
use strict;
use warnings;

use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 0;

use Test::More tests => 6;

use_ok 'MarpaX::Parse';
use_ok 'MarpaX::Parse::Tree';

# grammar
my $grammar = q{
    expr    ::= '-' num | num
    num     ::= digits | digits '.' digits
    digits  ::= digit | digit digits
    digit   ::= '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'
};

my $bnf = MarpaX::Parse->new({
    rules => $grammar,
    default_action => 'MarpaX::Parse::Tree::tree',
});

# input
my $numbers = [
    '1234',
    '-1234.423',
    '-1234',
    '1234.423',
];

# parse numbers
for my $number (@$numbers){
    my $tree = $bnf->parse($number);

    # reassemble the number from the digits
    my @digits;
    $tree->traverse(
        sub {
            my ($t) = @_;
            my $nv = $t->getNodeValue;
            given ($nv){
                when ("digit") {
                    push @digits, $t->getChild(0)->getNodeValue();
                }
                when ([ '.', '-' ]) {
                    push @digits, $nv;
                }
            }
        }
    );
    # compare the reassembled number with the input
    is join('', @digits), $number, "numeral $number parsed with pure BNF to a Tree::Simple parse tree";
}
