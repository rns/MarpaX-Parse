package Marpa::Easy::EBNF;

use 5.010;
use strict;
use warnings;

use YAML;

use Eval::Closure;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

# expressions in parens (factor)
my %subrules    = ();
my $subrule_no  = 0;

my $ebnf_rules = [
    
    # grammar ::= production+
    [ grammar => [qw( production+ )], sub {
        return @{ $_[1] } > 1 ? [ map { @$_ } @{ $_[1] } ] : $_[1];
    } ],
    
    # production ::= lhs '::=' rhs
    [ production => [qw( lhs ::= rhs )], 
        sub {
            shift;
            
            my ($lhs, undef, $rhs) = @_;
            
            my $rules;
            
#            say "=-" x 32;
#            say "# adding\n";

#            say "# production/lhs\n", $lhs;
#            say "# production/rhs\n", Dump $rhs;
#            say "# subrules\n", Dump \%subrules;
            
            # add rule
#            say "# rule:\n$lhs\n", Dump $rhs;
            # TODO: quantifier
            my $alt = $rhs->{alternation};
            my $qnt = $rhs->{quantifier};
            for my $seq ( map { $_->{sequence} } @$alt ){
                my @symbols = map { ref $_ eq "HASH" ? $_->{symbol} : "$lhs$_" } @$seq;
#                say "$lhs -> @symbols";
                push @$rules, [ $lhs, \@symbols ];
            }            
            
            # add subrules prepending the rule's $lhs
            for my $subrule_lhs (sort keys %subrules){
                my $subrule_rhs = $subrules{$subrule_lhs};
#                say "# subrule:\n$subrule_lhs\n", Dump $subrule_rhs;
                for my $seq (map { $_->{sequence} } @{ $subrule_rhs->{alternation} }){
                    my @symbols = map { ref $_ eq "HASH" ? $_->{symbol} : "$lhs$_" } @$seq;
                    # remove quantifiers
                    $subrule_lhs =~ s/\?|\*|\+//;
#                    say "$lhs$subrule_lhs -> @symbols";
                    push @$rules, [ "$lhs$subrule_lhs", \@symbols ];
                }            
            }
            
            # reinitialize
            %subrules    = ();
            $subrule_no  = 0;
            
            $rules;
        }
    ],
    
    # lhs ::= symbol
    [ lhs => [qw( symbol )] ],
    
    # rhs ::= term ('|' term)*
    { lhs => 'rhs', rhs => ['term'], min => 1, separator => '|', proper => 1, action =>
        sub {
            shift;
            { alternation => \@_ }
        }
    },
    
    # term ::= factor+
    { lhs => 'term', rhs => ['factor'], min => 1, proper => 1, action =>
        sub {
            shift;
            { sequence => \@_ }
        }
    },
    
    # factor ::= symbol
    [ factor => [qw(     symbol )], 
        sub { 
            { symbol => $_[1] }
        } 
    ], 
    
    # factor ::= symbol quantifier
    [ factor => [qw(     symbol quantifier )], 
        sub { 
            { symbol => "$_[1]$_[2]"  }
        } 
    ], 
    
    # factor ::= '(' rhs ')'
    [ factor => [qw( '(' rhs ')' )], 
        sub { 
            my $subrule = $_[2]; #{ symbols => $_[2] };

            # add subrule under provisional lhs
            my $prov_lhs = "__subrule" . $subrule_no++;
            $subrules{$prov_lhs} = $subrule;
            
            # return provisional lhs
            $prov_lhs;
        }
    ], 
    [ factor => [qw( '(' rhs ')' quantifier )], 
        sub { 
            my $subrule = $_[2];
#            $subrule->{quantifier} = $_[4];

            # add subrule under provisional lhs with quantifier
            my $prov_lhs = "__subrule" . $subrule_no++ . $_[4];
            $subrules{$prov_lhs} = $subrule;
            
            # return provisional lhs
            $prov_lhs;
        } 
    ], 

    [ quantifier => [qw( '?' )] ], 
    [ quantifier => [qw( '*' )] ], 
    [ quantifier => [qw( '+' )] ], 

    [ symbol     => [qw( identifier )] ],
    [ symbol     => [qw( literal    )] ],

];

sub rules { $ebnf_rules }

my $balanced_terminals = {
    '".+?"' => 'literal',
    "'.+?'" => 'literal',
};
my $balanced_terminals_re = join '|', keys %$balanced_terminals;

my $literal_terminals = {
    '::=' => '::=',
    '|' => '|',
    '(' => "'('",
    ')' => "')'",
    '?' => "'?'",
    '*' => "'*'",
    '+' => "'+'",
};
my $literal_terminals_re = join '|', map { quotemeta } keys %$literal_terminals;
# and the rest must be symbols

sub lex_ebnf_text
{
    my $self = shift;
    
    my $ebnf_text = shift;
    
    my $tokens = [];
    
#    say $ebnf_text;
    
    # trim ebnf text
    $ebnf_text =~ s/^\s+//s;
    $ebnf_text =~ s/\s+$//s;

    # remove comments at line start and trim
    $ebnf_text =~ s/^#.*?$//mg;
    $ebnf_text =~ s/^\s+//s;
    $ebnf_text =~ s/\s+$//s;
    
    # split on balanced
    for my $on_balanced (split /($balanced_terminals_re)/s, $ebnf_text){
        
        # trim
        $on_balanced =~ s/^\s+//s;
        $on_balanced =~ s/\s+$//s;
#        say "on balanced: <$on_balanced>";

        # find balanced terminals
        if ($on_balanced =~ /^$balanced_terminals_re$/s){
            for my $re (keys %$balanced_terminals){
                if ($on_balanced =~ m/^$re$/s){
#                    say $balanced_terminals->{$re}, ": ",$on_balanced;
                    push @$tokens, [ $balanced_terminals->{$re}, $on_balanced ];
                }
            }      
        }
        else{

            # remove comments and trim
            $on_balanced =~ s/#.*?$//mg;
            $on_balanced =~ s/^\s+//s;
            $on_balanced =~ s/\s+$//s;
            
            # split on literals
            for my $on_literal (split /($literal_terminals_re)/s, $on_balanced){
                $on_literal =~ s/^\s+//s;
                $on_literal =~ s/\s+$//s;
#                say "on literal: <$on_literal>";
                # find literal terminals
#                say "on literal: <$on_literal>";
                if ($on_literal =~ /^$literal_terminals_re$/){
                    for my $re (keys %$literal_terminals){
                        if ($on_literal =~ m/^\Q$re\E$/){
#                            say $literal_terminals->{$re}, ": ",$on_literal;
                            push @$tokens, [ $literal_terminals->{$re}, $on_literal ];
                        }
                    }      
                }
                else{
                    for my $identifier (split /\s+/s, $on_literal){
                        $identifier =~ s/^\s+//s;
                        $identifier =~ s/\s+$//s;
#                        say "identifier: $identifier";
                        push @$tokens, [ 'identifier', $identifier ];
                    }
                }
            }
        }
    }

#    say "# ebnf tokens ", Dump $tokens;
    return $tokens; 
}

1;
