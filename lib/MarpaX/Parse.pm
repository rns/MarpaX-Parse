package MarpaX::Parse;

use 5.010;
use strict;
use warnings;

use Carp qw{cluck};

use YAML;

use Marpa::R2;

use Tree::Simple 'use_weak_refs';
use Tree::Simple::Visitor;
use Tree::Simple::View::DHTML;
use Tree::Simple::View::HTML;

use Data::TreeDumper;

use MarpaX::Parse::BNF;
use MarpaX::Parse::EBNF;

use Math::Combinatorics;

use Encode qw{ encode is_utf8 };

use XML::Twig;

use Clone qw(clone);

=head1 Synopsys

input and output, e.g. 
    input: decimal number
    output: power series of that number

rules
    - BNF grammar (scalar); or 
    - Marpa::R2 rules array ref

actions
    - can be deferred until parsing    

grammar

    BNF parsing 

        $bnf_parser
        produces parsed rules to be transformed into Marpa::R2 rules 

    rules transformation    
        produces transformed rules; includes
        - closures extraction
        - adding rules for quantifier symbols
        - default_action and start rule setting 
        - lexer rules extraction (literals)
    
    Marpa::R2::Grammar
        -- its rules become the value of 'rules' options 

parsing of input    
    
    input can be 
        - scalar (string); or 
        - arrays of tokens (unambiguous or ambiguous)

    lexing
        scalar input is lexed by 
            pre-lexing
                - extrating literals from the grammar
                - setting them up as regex => token name hash
            lexing
                - matching input and consuming the longest match
        tokens    
    
    recognizing (Marpa::R2)
        produces Marpa::R2 parse tree
        
    evaluation (Marpa::R2)
        produces parse value that can be 
            - final value
            - tree to be evaluated by the application
    
evaluation of parse by the application
    
    default_action settings produce parse trees:
    
        - 'tree'    Tree::Simple 
        - 'xml'     XML string
        - 'sexpr'   S-expression
        - 'AoA'     array of array
        - 'HoA'     hash of arrays
        - 'HoH'     hash of arrays
    
    that can be further evaluated by the application 
    
    Details are in 
        10_parse_tree_simple.t
        11_parse_tree_xml.t
        13_decimal_number_power_expansion_bnf_parse_trees_vs_actions.t
    
=cut

#
# Any BNF grammar passed to MarpaX::Parse by setting <rules> to scalar 
# is parsed by the BNF parser with rules set in MarpaX::Parse::BNF
#
# BNF parser tokens, rules and closures are shown by show_bnf_parser_* options
# 
# tokens, rules and closures of the BNF grammar passed to MarpaX::Parse are shown
# by show_bnf_* options
# 
# Finally, tokens, rules and closures of the input parsed by the BNF grammar passed 
# to MarpaX::Parse are shown # by show_* options
#

my $marpa_easy_options = {

    # stage: BNF grammar parser initialization
    show_bnf_parser_tokens => undef,
    show_bnf_parser_rules => undef,    
    show_bnf_parser_closures => undef, 
    show_parsed_bnf_rules => undef,    
    
    # stage: parsing the BNF grammar text set as <rules> option
    show_bnf_tokens => undef,
    show_bnf_rules => undef,    
    show_bnf_closures => undef, 
    
    # stage: pre-lexing
    # extracting lexer rules from the grammar rules (terminal literals)
    show_literals => undef,
    show_lexer_rules => undef,
    # setting up lexer regexes based on lexer rules 
    show_lexer_regexes => undef,

    # stage: lexing input for parsing (BNF parser and input)
    show_input => undef,
    show_tokens => undef,
    
    # stage: transforming BNF or Marpa::R2 rules passed in 'rules' option 
    # and setting up the grammar based on them
    show_rules => undef,
    show_closures => undef,
    
    # stage: parsing input with BNF or Marpa::R2 rules passed in 'rules' option
    show_symbols => undef,
    show_terminals => undef,
    
    # stage: recognition by Marpa::R2 
    show_recognition_failures => undef,
    recognition_failure_sub => undef,

    # transform quantified symbols into sequence (by default) or recursive rules
    quantifier_rules => undef,
    
    # if true, nullable symbols will be added instead removing the rules 
    # with ?/*-quanfitied symbols
    nullable_quantified_symbols => undef,
    
    # handle ambuous tokens with input model (alternate()/earleme_complete()
    ambiguity => undef,
    
    ebnf => undef,
};

#
# BNF parser needs to be package variable of MarpaX::Parse
# to prevent repeated transformation of its rules
#   
# BNF parser grammar setup
my $bnf_parser = MarpaX::Parse->new({ 
    rules => MarpaX::Parse::BNF::rules,
    default_action => 'AoA',
});

# EBNF parser grammar setup
my $ebnf_parser = MarpaX::Parse->new({ 
    rules => MarpaX::Parse::EBNF::rules,
    default_action => 'AoA',
});

sub new{

    my $class = shift;
    my $options = shift;
    
    my $self = {};
    bless $self, $class;
    
    $self->build($options);
    
    return $self;
}

sub build{
    
    my $self = shift;
    
    my $options = shift;
    
    # clone options to enable adding rules to grammar
    $self->{options} = clone $options;
    
    # extract MarpaX::Parse options and set defaults
    while (my ($option, $value) = each %$options){
        if (exists $marpa_easy_options->{$option}){
            $self->{$option} = $value;
            delete $options->{$option};
        }
    }
    # set defaults
    $self->{quantifier_rules}               //= 'sequence';
    $self->{nullable_quantified_symbols}    //= 0;
    $self->{ambiguity}                      //= 'input_model';
    $self->{recognition_failure_sub}        //= \&recognition_failure;
    
    # TODO: extract recognizer options
    my @recognizer_options = qw{
        closures
        end
        event_if_expected
        max_parses
        ranking_method
        too_many_earley_items
        trace_actions
        trace_file_handle
        trace_terminals
        trace_values
        warnings
    };
    
    # transform rules
    my @rules;

    # indicate that BNF grammar scalar rather than rules aref was passed
    my $bnf = 0;

    # array ref means we have rules
    if (ref $options->{rules} eq "ARRAY"){  
        @rules = @{ $options->{rules} };
    }
    # scalar means we have a BNF grammar we need to parse to get rules
    else {
        $bnf = 1;
        my $rules;
        # ebnf (contains grouping (non-literal) parens)
        if ($self->{ebnf}){ 
            $rules = $self->_ebnf_to_rules( $options->{rules} );
        }
        # bnf
        else{ 
            $rules = $self->_bnf_to_rules( $options->{rules} );
        }
        # TODO: catch BNF parsing errors, e.g. := not ::=
        @rules = @$rules;
        $self->set_option('parsed_bnf_rules', \@rules);
    }

    # quantifiers to rules
    $self->_quantifiers_to_rules( \@rules );

    # extract closures and generate actions for Recognizer
    my $closures = _closures_to_actions( \@rules );
    $self->{closures} = $closures;

    # handle default action
    $self->_set_default_action($options);    
    
    # set start to lhs of the first rule if not set
    if (not exists $options->{start}){
        $options->{start} = _extract_start_symbol( \@rules );
    }

    # save transformed rules for further adding to them 
    $self->set_option('transformed_rules', \@rules);
    
    # set transformed rules as Marpa grammar option
    $options->{rules} = \@rules;
    
    # set up the grammar
    my $grammar = Marpa::R2::Grammar->new($options);
    $grammar->precompute();
    
    # save the grammar
    $self->{grammar} = $grammar;
    
    # set rules option
    $self->set_option('rules', $grammar->show_rules);
    
    # save bnf rules
    if ($bnf){
        $self->set_option('bnf_rules', $grammar->show_rules);
    }
    
    # extract save terminals for lexing
    my $terminals = $self->_extract_terminals( \@rules, $grammar );
    
    # extract and save lexer rules
    $self->set_option('lexer_rules', $self->_extract_lexer_rules( $options->{rules} ) );
}

# print a variable with comment and stack trace
sub _dump {
    my $comment     = shift || "";
    my $var         = shift;
    my $stack_trace = shift || 0;
    
#    cluck "_dump";
    
    my $dump = ref $var ? 
        DumpTree( $var, "# $comment:", DISPLAY_ADDRESS => 0, DISPLAY_OBJECT_TYPE => 0 )
        :
        "# $comment:\n$var";
    
    $stack_trace ? cluck $dump : say $dump;
}

#
# get current options (as-passed), get rules from them, merge new rules, 
# and rebuild MarpaX::Parse
# 
sub merge_token_rules { 
    
    my $self = shift;

    my $token_rules = shift;

    # get initial options
    my $options = $self->{options};
    
    # $token_rules and $options->{rules} need to be both array refs or scalars (strings)
    if (ref $token_rules eq "ARRAY" and ref $options->{rules} eq "ARRAY"){
        # merge arrays
        push @{ $options->{rules} }, @$token_rules;
        
    }
    elsif (ref $token_rules eq "" and ref $options->{rules} eq ""){
        # merge texts
        $options->{rules} .= $token_rules;
    }
    
    # rebuild
    $self->build($options);
}

sub grammar { $_[0]->{grammar} }

# set the value to {$option} key to be printed if "show_$option" is set in the constructor
sub set_option{

    my $self = shift;

    my $option = shift;
    my $value = shift;

    $self->{"$option"} = $value;
}

# stringify tokens as name[ name]: value
sub _token_string {

    my $token = shift;
    
    my $_token_string;
    
    # ambigious token
    if (ref $token->[0] eq "ARRAY"){ 
        $_token_string = join(": ", join(' ', map { $_->[0] } @$token), $token->[0]->[1]);
    }
    # unambigious token
    else{ 
        $_token_string = join (': ', @$token);
    }
    
    return $_token_string;
}

# return show_$option value or say show_$option's value if show_$option is set to true in the constructor
sub get_option{

    my $self = shift;

    my $option = shift;
    my $value = $self->{$option} || ''; #cluck "value of option '$option' undefined";

    # stringify the option value
    if (ref $value ~~ ["ARRAY", "HASH"]){
        # tokens
        if ($option eq 'tokens'){
            $value = join "\n", map { _token_string($_) } @$value;
        }
        # rules
        elsif ($option eq 'rules'){
            my $rules = $self->grammar->show_rules; 
            $value = $rules;
        }
        # symbols
        elsif ($option eq 'symbols'){
            my $symbols = $self->grammar->show_symbols;
            $value = $symbols;
        }
        # terminals
        elsif ($option eq 'terminals'){
            $value = join "\n", sort @{ $self->{terminals} }
        }
        # lexer rules
        elsif ($option eq 'lexer_rules'){
            my $lr = $self->{lexer_rules};
            $value = join "\n", map { join ': ', $_, $lr->{$_} } sort keys %$lr;
        }
        # recognition failures        
        elsif ($option eq 'recognition_failures'){
            $value = @{ $self->{$option} } ? _dump ("recognition failures", $self->{$option}) : "";
        }
        # anything else
        else{
            $value = Dump $value;
            $value =~ s/^---\n//s;
        }
    } ## stringify the option value

    # set empty value for undefined options
    $value //= '';
    
    # remove newlines, if any
    chomp $value;
    
    return $value;
}

sub comment_option {
    my $self = shift;

    # we derive the comment from the option
    my $comment = shift; 

    # make the comment more readable
    $comment =~ s/_/ /g;
    $comment =~ s/bnf/BNF/g;
    
    return "# $comment:";
}

# print the value of $option to stdout if show_$option is set to true in the constructor
sub show_option{
    my $self = shift;

    my $option = shift;

    if (exists $self->{"show_$option"}){
        my $value = $self->get_option($option);
        if ($value){
            my $comment = $self->comment_option($option);
            say join "\n", $comment, $value;
        }
    }
}

# options getters

sub show_parsed_bnf_rules       { $_[0]->get_option('parsed_bnf_rules') }
sub show_transformed_bnf_rules  { $_[0]->get_option('transformed_bnf_rules') }
sub show_closures               { $_[0]->get_option('closures') }

sub show_bnf_tokens             { $_[0]->get_option('bnf_tokens') }
sub show_bnf_rules              { $_[0]->get_option('bnf_rules') }
sub show_bnf_closures           { $_[0]->get_option('bnf_closures') }

sub show_tokens                 { $_[0]->get_option('tokens') }
sub show_rules                  { $_[0]->get_option('rules') }
sub show_symbols                { $_[0]->get_option('symbols') }
sub show_terminals              { $_[0]->get_option('terminals') }

sub show_lexer_rules            { $_[0]->get_option('lexer_rules') }
sub show_literals               { $_[0]->get_option('literals') }

sub show_lexer_regexes          { $_[0]->get_option('lexer_regexes') }

sub show_recognition_failures   { $_[0]->get_option('recognition_failures') }

# parse BNF to what will become Marpa::R2 rules after transformation 
# (extraction of closures, adding rules for quantifiers, extraction of lexer rules, etc.)
sub _bnf_to_rules
{
    my $self = shift;
    
    my $bnf = shift;
    
    # parse bnf
    my $bnf_tokens = MarpaX::Parse::BNF->lex_bnf_text($bnf);

    # save bnf tokens
    $self->set_option('bnf_tokens', join "\n", map { join ': ', @$_ } @$bnf_tokens);

    # show BNF tokens if the option is set
    # say "# BNF tokens:\n", $self->show_bnf_tokens if $self->{show_bnf_tokens};
    $self->show_option('bnf_tokens');
    
    # $bnf_parser is a package variable
    # TODO: show bnf parser tokens, rules, and closures if the relevant options are set
    
    # parse BNF tokens to Marpa::R2 rules
    my $rules = $bnf_parser->parse($bnf_tokens);
    
    return $rules;
}

sub _ebnf_to_rules
{
    my $self = shift;
    
    my $ebnf = shift;

#    say Dump $ebnf;
    
    # parse ebnf
    my $ebnf_tokens = MarpaX::Parse::EBNF->lex_ebnf_text($ebnf);
    
#    say "# EBNF tokens:\n", Dump $ebnf_tokens;
    
    # save ebnf tokens
    $self->set_option('ebnf_tokens', join "\n", map { join ': ', @$_ } @$ebnf_tokens);

    # show EBNF tokens if the option is set
    
#    say "# EBNF tokens:\n", $self->show_bnf_tokens if $self->{show_ebnf_tokens};
#    $self->show_option('ebnf_tokens');
    
    # $bnf_parser is a package variable
    # TODO: show bnf parser tokens, rules, and closures if the relevant options are set
    
    # parse EBNF tokens to Marpa::R2 rules
#    say "# parsing EBNF";
#    say $ebnf_parser->show_rules;
    my $rules = $ebnf_parser->parse($ebnf_tokens);
    
#    say Dump $rules;
    
    return $rules;
}

=head2
    
    For each symbol ending with * or + add a Marpa sequence rule 
    with lhs being the symbol, rhs being symbols without the quantifier 
    the min => 0 or min => 1, respectively
    
    For each symbol ending with ?, add a new rule without such symbol
    and remove ? from the symbol's end. 
    
    Several symbols may be zero (? *)-quantified and all needed rules will be added.
    
=cut
sub _quantifiers_to_rules
{   
    my $self = shift;
    
    my $rules = shift;
    
#    say "# rules ", Dump $rules;
    
    # symbols quantified with * or + require adding sequence rules
    my $quantified_symbol_rules = [];

    # symbols quantified with * or ? require adding rules without such symbols
    # more than one symbol per rules can be  * or ? quantified hence 
    # $nullable_symbol_indices->{quantified_rule_index}->{nullable_symbol_index}
    my $nullable_symbol_indices = {};
    
    # prevent duplication of sequence rules' lhs 
    my $sequence_lhs = {}; 

    # process rules
    for my $j (0..@$rules-1){
        my $rule = $rules->[$j];
#        say "# rule ", Dump $rule;
        # get lhs and rhs
        my ($lhs, $rhs);
        given (ref $rule){
            when ("HASH"){
                $lhs = $rule->{lhs};
                $rhs = $rule->{rhs};
            }
            when ("ARRAY"){
                ($lhs, $rhs) = @$rule;
            }
        }
#        say "# $lhs -> ", Dump $rhs;
        # check symbols ending with quantifiers
        for my $i (0..@$rhs-1){
            my $symbol = $rhs->[$i];
            # TODO: better checking for regexes (\d+)
            if ($symbol =~ m/(\?|\*|\+)$/ and $symbol !~ m{\\}){
                my $quantifier = $1;
#                say "$quantifier, $rhs->[$i]";
                # setup sequence item ($symbol without quantifier)
                my $non_quantified_symbol = $symbol;
                $non_quantified_symbol =~ s/\Q$quantifier\E$//;
#                say "$quantifier, $rhs->[$i], $symbol";
                # dispatch on quantifier
                given ($quantifier){
                    when ("?"){
#                        say "# zero or one ", Dump $rule;
                        # set rule's nullable symbol indices
                        $nullable_symbol_indices->{$j}->{$i} = undef;
                        # replace quantified symbol to non-quantified in the rule
                        $rhs->[$i] = $non_quantified_symbol;
                    }
                    # add min => 0 or min => 1 sequence 
                    when ([qw(* +)]){
                        
                        # sequence lhs must be unique
                        unless (exists $sequence_lhs->{$symbol} ){
                            if ($self->{quantifier_rules} eq 'recursive'){
#                                say "sequences as recursive rules";
                                my $item = $non_quantified_symbol;
                                my $seq = $symbol;
                                # seq ::= item
                                push @$quantified_symbol_rules, { 
                                    lhs     => $seq,
                                    rhs     => [ $item ],
                                    action  => sub { 
                                        [ $_[1] ];
                                    },
                                };
                                # seq ::= item seq
                                push @$quantified_symbol_rules, { 
                                    lhs     => $seq,
                                    rhs     => [ $seq, $item ],
                                    action  => sub { 
#                                        say Dump \@_;
                                        if (ref $_[1] eq "" and ref $_[2] eq ""){
                                            return ($_[1] ? $_[1] : '') . ($_[2] ? $_[2] : '');
                                        }
                                        else{
                                            push @{ $_[1] }, $_[2];
                                        }
                                        return $_[1];
                                    },
                                };
                            }
                            else{
#                                say "sequences as sequence rules";
                                push @$quantified_symbol_rules, { 
                                    lhs => $symbol,
                                    rhs => [ $non_quantified_symbol ],
                                    min => $quantifier eq '+' ? 1 : 0,
#                                    action => sub { 
                                        # strip per-parse variable
#                                        shift;
    #                                    say Dump \@_;
    #                                    say defined @_;
    #                                    say join '', @_;
                                        # return empty array ref rather than undef for null (zero-item) sequences
#                                        \@_;
#                                    },
                                };
                            }
                            $sequence_lhs->{$symbol} = undef;
                        }
                        # set rule's nullable symbol indices
                        if ($quantifier eq '*'){
                            $nullable_symbol_indices->{$j}->{$i} = undef;
                        }
                    }
                }
            }
        }
    }
    
    # add rules for quantified symbols
#    say Dump $quantified_symbol_rules;
    push @$rules, @$quantified_symbol_rules;

    # just add [ nullable_symbol => [] ] rules if the options are set
    if ($self->{nullable_quantified_symbols} and $self->{quantifier_rules} eq 'recursive'){
        my @nullables;
        for my $j (keys %$nullable_symbol_indices){
            my $rule = $rules->[$j];

            my ($lhs, $rhs);
            given (ref $rule){
                when ("HASH"){
                    $lhs = $rule->{lhs};
                    $rhs = $rule->{rhs};
                }
                when ("ARRAY"){
                    ($lhs, $rhs) = @$rule;
                }
            }

            my @nullables = sort keys %{ $nullable_symbol_indices->{$j} };
            for my $nullable (@nullables){
#                say $rhs->[$nullable];
                push @$rules, [ $rhs->[$nullable] => [] ];
            }
        }
    }
    else {
        # generate and add rules with nullable symbols
        my @rules_with_nullables;
        for my $j (keys %$nullable_symbol_indices){
            my $rule = $rules->[$j];

            my ($lhs, $rhs);
            given (ref $rule){
                when ("HASH"){
                    $lhs = $rule->{lhs};
                    $rhs = $rule->{rhs};
                }
                when ("ARRAY"){
                    ($lhs, $rhs) = @$rule;
                }
            }

            my @nullables = sort keys %{ $nullable_symbol_indices->{$j} };
            # generate the indices of symbols to null
    #        say "$lhs -> @$rhs\nnullables:@nullables";
            my @symbols_to_null;
            for my $k (1..@nullables){
                my @combinations = combine($k, @nullables);
                push @symbols_to_null, \@combinations;
    #            say "$k:", join ' | ', map { join ' ', @$_ } @combinations;
            }
            # generate nullables rhs by deleting nullable symbols according to generated indices
            for my $combinations (@symbols_to_null){
                # delete (null) nullable symbols
                for my $combination (@$combinations){
    #                say "@$combination";
                    my @nullable_rhs = @$rhs;
                    for my $index (@$combination){
                        $nullable_rhs[$index] = undef;
                    }
                    @nullable_rhs = grep {defined} @nullable_rhs;
    #                say "$lhs -> @nullable_rhs";
                    push @rules_with_nullables, { lhs => $lhs, rhs => \@nullable_rhs };
                }
            }
        }
    #    say Dump \@rules_with_nullables;
        push @$rules, @rules_with_nullables;
    }
    
}

sub _extract_start_symbol
{
    my $rules = shift;
    
    my $rule0 = $rules->[0];
    
    my $start = ref $rule0 eq "HASH" ? $rule0->{lhs} : $rule0->[0];
    
    return $start;
}

sub _set_default_action
{
    my $self = shift;
    
    my $options = shift;
    
    # if default action exists in this package then use it
    my $da = $options->{default_action};
    if (defined $da){
        if (exists $MarpaX::Parse::{$da}){
            $options->{default_action} = __PACKAGE__ . '::' . $da;
        }
    }
    # otherwise set _default_action which prints the rules and their contents
    else{
        $options->{default_action} = __PACKAGE__ . '::' . 'AoA';
    }
    $self->{default_action} = $options->{default_action};
}

# lexer rules are derived from literal terminals, which can be 
# strings or qr// patterns in single or double quotes
sub _extract_lexer_rules
{
    my $self = shift;
    
    my $rules = shift;
    my $terminals = $self->{terminals};
    
    $self->show_option('rules');
    $self->show_option('symbols');
    $self->show_option('terminals');

    my $lr = {};

    # lexer rules are formed by terminals wrapped in single or double quotes
    my @literals;
    for my $terminal (@$terminals){
#        say "# terminal:\n", $terminal;
        if (
            (substr($terminal, 0, 1) eq '"' and substr($terminal, -1) eq '"') or
            (substr($terminal, 0, 1) eq "'" and substr($terminal, -1) eq "'")
            ){
            push @literals, $terminal;
            my $literal = substr $terminal, 1, -1;
#            say "# lexer rule: <$literal> -> <$terminal>";
            $lr->{$literal} = $terminal;
        }
    }
    # save and show literals if show_literals is set
    $self->set_option('literals', join "\n", sort @literals );
    $self->show_option('literals');
    
    return $lr;
}

sub _extract_terminals
{
    my $self = shift;
    
    my $rules = shift;
    my $grammar = shift;
    
    my $symbols = $self->_extract_symbols($rules);
    
    my $terminals = [];
    for my $symbol (keys %$symbols){
        if ($grammar->check_terminal($symbol)){
            push @$terminals, $symbol;
        }
    }
    $self->{terminals} = $terminals;
    
    return $terminals;
}

sub _extract_symbols
{
    my $self = shift;
    
    my $rules = shift;
    
    my $symbols = {};
    
    for my $rule (@$rules){
        my ($lhs, $rhs);
        given (ref $rule){
            when ("HASH"){
                # get the rule's parts
                $lhs = $rule->{lhs};
                $rhs = $rule->{rhs};
            }
            when ("ARRAY"){
                # get the rule's parts
                ($lhs, $rhs) = @$rule;
            }
        }
        for my $symbol ($lhs, @$rhs){
            $symbols->{$symbol} = undef;
        }
    }
    $self->{symbols} = $symbols;
    
    return $symbols;
}

sub _rule_signature
{
    my ($lhs, $rhs) = @_;
    return "$lhs -> " . join ' ', @$rhs;
}

sub _action_name
{
    return "action(" . _rule_signature(@_) . ")";
}

sub _closures_to_actions
{
    my $rules = shift;
    
#    say "# _closures_to_actions: rules:\n", Dump $rules;
    
    my $closures = {};
    
    for my $rule (@$rules){
        my ($lhs, $rhs, $closure);
        given (ref $rule){
            when ("HASH"){
                # get the rule's parts
                $lhs = $rule->{lhs};
                $rhs = $rule->{rhs};
                $closure = $rule->{action};
                # we need anonymous subs and not the action names
                if (defined $closure and ref $closure eq "CODE"){
                    # make action name
                    my $an = _action_name($lhs, $rhs);
                    # replace closure with action name
                    $closures->{$an} = $closure;
                    # add closure for recognizer
                    $rule->{action}  = $an;
                }
            }
            when ("ARRAY"){
                # get the rule's parts
                ($lhs, $rhs, $closure) = @$rule;
                # we need anonymous subs and not the action names
                if (defined $closure  and ref $closure eq "CODE"){
                    # make action name
                    my $an = _action_name($lhs, $rhs);
                    # replace closure with action name
                    $rule->[-1]      = $an;
                    # add closure for recognizer
                    $closures->{$an} = $closure;
                }
            }
        }
        
    }
    
#    say "# _closures_to_actions: closures:\n", Dump $closures;
    
    return $closures;
}

sub AoA { 

    # The per-parse variable.
    shift;

    # Throw away any undef's
    my @children = grep { defined } @_;
    
    # Return what's left as an array ref or a scalar
    scalar @children > 1 ? \@children : shift @children;
}

sub HoA { 

    # The per-parse variable.
    shift;

    # Throw away any undef's
    my @children = grep { defined } @_;
    
    # Get the rule's lhs
    my $lhs = ($Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule))[0];
    
    # Return what's left as an array ref or a scalar named after the rule's lhs
    return { $lhs => scalar @children > 1 ? \@children : shift @children }
}

sub HoH { 

    # The per-parse variable.
    shift;

    # Get the rule's lhs
    my $lhs = ($Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule))[0];

    # Throw away any undef's
    my @children = grep { defined } @_;
    
    # Return what's left as an array ref or a scalar
    my $result = {};
#    say "# children of $lhs\n", Dump \@children;
    if (@children > 1){
        for my $child (@children ){
            if (ref $child eq "HASH"){
#                say "# child of $lhs (HASH):\n", Dump $child;
                for my $key (keys %$child){
                    # replace duplicate key to array ref
                    if (exists $result->{$lhs}->{$key}){
                        $result->{$lhs}->{$key} = [ values %{ $result->{$lhs} } ] 
                            unless ref $result->{$lhs}->{$key} eq "ARRAY";
                        push @{ $result->{$lhs}->{$key} }, values %{ $child };
                    }
                    else{
                        $result->{$lhs}->{$key} = $child->{$key};
                    }
                }
            }
            elsif (ref $child eq "ARRAY"){
#                say "# child of $lhs (ARRAY):\n", Dump $child;
                # issue warning when destination key already exists
                if (exists $result->{$lhs}){
                    say "This value of {$lhs}:\n", Dump($result->{$lhs}), "will be replaced with:\n", Dump($child);
                }
                $result->{$lhs} = $child;
            }
        }
    }
    else {
        $result->{$lhs} = shift @children;
    }        
    return $result;
}

sub AoA_with_rule_signatures { 

#    say "# AoA_with_rule_signatures ", Dump \@_;

    # per-parse variable.
    shift;
    
    # Throw away any undef's
    my @children = grep { defined } @_;
    
    # Return what's left as an array ref or a scalar
    my $result = scalar @children > 1 ? \@children : shift @children;
    
    # Get the rule lhs and rhs and make the rule signature
    my ($lhs, @rhs) = $Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule);
    my $rule = $lhs . ' -> ' . join ' ', @rhs;

    $result = [ $result ];
    unshift @$result, $rule;

    return $result;
}

# s-expression
sub sexpr { 

    # The per-parse variable.
    shift;
    
    # Get the rule's lhs
    my $lhs = ($Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule))[0];
    
    # Throw away any undef's
    if (my @children = grep { defined } @_){
        return "($lhs " . join(' ', map { ref $_ eq "ARRAY" ? join ' ', @$_ : $_ } @children) . ")";
    }
    
    return undef; 
}

sub tree { 

    # The per-parse variable.
    shift;
    
    my @children = grep { defined } @_;
    
    if (@children){
#        say "# tree:\n", Dump [ map { ref $_ eq 'Tree::Simple' ? ref $_ : $_ } @children ];

        # get the rule's lhs
        my $lhs = ($Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule))[0];

        # set up the parse tree node
        my $node = Tree::Simple->new($lhs);
        $node->addChildren(
            map { 
                    ref $_ eq 'Tree::Simple' 
                        ? $_ 
                        : ref $_ eq "ARRAY" 
                            ? map { ref $_ eq 'Tree::Simple' 
                                ? $_ 
                                    : Tree::Simple->new($_) } grep { defined $_ } @$_ 
                                : Tree::Simple->new($_) 
                } 
                @children
        );

        return $node;
    }

    return undef;
}

# remove unneeded Tree::Simple information from Data::TreeDumper's output
sub filter
{
    my $s = shift;

    if('Tree::Simple' eq ref $s){
        my $counter = 0;
        return (
            'ARRAY', 
            $s->{_children}, 
            # index generation
            map 
                { 
                    [ $counter++, $_->{_node} ] 
                } 
                @{ 
                    $s->{_children}
                }
        );
    }
    
    return(Data::TreeDumper::DefaultNodesToDisplay($s)) ;
}

sub xml {

#    say Dump \@_;
    
    # The per-parse variable.
    shift;
    
    # Get the rule's lhs
    my $lhs = ($Marpa::R2::Context::grammar->rule($Marpa::R2::Context::rule))[0];
    
    # replace symbols quantifier symbols (not valid in XML tags) with plural (hopefully)
    $lhs =~ s/(\+|\*)$/s/;
    
    # wrap xml element
    return 
          "<$lhs>" 
        . join( "", map { ref $_ eq "ARRAY" ? join "", @$_ : $_ } grep { defined } @_ ) 
        . "</$lhs>";
}

sub show_parse_tree{
    my $self = shift;
    my $tree = shift || $self->{parse_tree};
    my $format = shift || 'text';
    
    # handle multiple parses
    if (ref $tree eq "ARRAY" and $self->{multiple_parse_trees} > 1
        and $self->{default_action} ne __PACKAGE__ . '::AoA_with_rule_signatures'){
        my $trees = '';
        for my $i (0..@$tree-1){
            $trees .= "# Parse Tree @{[$i+1]}:\n" . $self->show_parse_tree($tree->[$i], $format) . "\n";
        }
        chomp $trees;
        return $trees;
    }
    else{
        # tree proper
        if (ref $tree eq "Tree::Simple"){
            given ($format){
                when ("text"){
                    return DumpTree( 
                            $tree, $tree->getNodeValue,
                            DISPLAY_ADDRESS => 0,
                            DISPLAY_OBJECT_TYPE => 0,
                            FILTER => \&filter
                        );
                }
                when ("html"){
                    my $tree_view = Tree::Simple::View::HTML->new($tree);    
                    return $tree_view->expandAll();
                }
                when ("dhtml"){
                    my $tree_view = Tree::Simple::View::DHTML->new($tree);    
                    return 
                          $tree_view->javascript()
                        . $tree_view->expandAll();
                }
            }
        }
        # data structure
        elsif (ref $tree ~~ [ "ARRAY", "HASH" ] ){
            return DumpTree($tree, "tree",
                DISPLAY_ADDRESS => 0,
                DISPLAY_OBJECT_TYPE => 0,
            )
        }
        # utf8 string, must be XML
        elsif (is_utf8($tree) and index ($tree, "<\?xml/") >= 0) {
            my $t = XML::Twig->new(pretty_print => 'indented');
            $t->parse($tree);
            return $t->sprint;
        }
        # mere scalar
        else{
            return $tree;
        }
    }
}

# TODO: pluggable lexer (Parse::Flex, etc.)
sub lex
{
    my $self = shift;
    
#    say "# lexing: ", Dump \@_;
    
    my $input = shift;
    
    my $lex = shift || $self->{lexer_rules};

    $self->set_option('input', $input);
    $self->show_option('input');
   
    $self->show_option('rules');
    $self->show_option('symbols');
    $self->show_option('terminals');
    $self->show_option('literals');

    $self->show_option('lexer_rules');

    # TODO: add 'default' rule (as in given/when) to apply when 
    # none of the other rules matched (for BNF parsing)

    # make regexes of strings and qr// in strings leaving regexes proper as is
    my $lex_re = {};
    for my $l (keys %$lex){
#say "terminal: <$l>";    
        my $l_re = $l;
        if ($l =~ /^\Q(?^:\E/){
#say "regex: $l";
        }
        elsif ($l =~ m{^qr/.*?/\w*$}){
#say "qr in string: $l";
            $l_re = eval $l;
        }
        else{
#say "string: $l";
            $l_re = qr/\Q$l\E/;
        }
        $lex_re->{$l_re} = $lex->{$l};
    }
    $self->{lexer_regexes} = $lex_re;
    chomp $self->{lexer_regexes};
    $self->show_option('lexer_regexes');

    my $tokens = [];
    my $i;

    my $max_iterations = 1000000;

    $self->show_option('show_input');
        
    while ($i++ < $max_iterations){
        # trim input start
        $input =~ s/^\s+//s;
        $input =~ s/^\s+//s;
#say "# input: <$input>";
        # match reach regex at string beginning
        my $matches = {};
        for my $re (keys %$lex_re){
            if ($input =~ /^($re)/){
#say "match: $re -> '$1'";
                $matches->{$1}->{$lex_re->{$re}} = undef;
            }
        }
#say Dump $matches;
        # no matches means the end of lexing
        my @matches = keys %$matches;
        last unless @matches;
        # sort matches by length (longest first)
        @matches = sort { length $b <=> length $a } @matches;
        # get longest match(es)
        my $max_len = length $matches[0];
        my @max_len_tokens = grep { length $_ eq $max_len } @matches;
        # set [ token_name, token_value ] pairs
        my @matched_tokens;
        # get token names of token values
        for my $token_value (@max_len_tokens){
            my @token_names = keys %{ $matches->{$token_value} };
            for my $token_name (@token_names){
    #            say "$token_name, $token_value";
                push @matched_tokens, [ $token_name, $token_value ];
            }
        }
        if (@matched_tokens > 1){ # ambigious tokens
            push @$tokens, \@matched_tokens;
        }
        else{
            push @$tokens, $matched_tokens[0];
        }

        # trim the longest match from the string start
        $input =~ s/^\Q$max_len_tokens[0]\E//;
    }
    warn "This must have been an infinite loop: maximum interations count $max_iterations exceeded" if $i > $max_iterations;
    push @$tokens, [ '::any', $input ] if $input;
    
    $self->{tokens} = $tokens;
    
    return $tokens;
}

# recognition failures are not necessarily fatal so by default, 
# this sub will be called to get the most out of the recognizer and set that 
# as recognition failure item under recognition_failures option
# that can be further retrieved by show_recognition_failures
# this default sub is here for demonstration only and cannot be considered as
# any guide.
sub recognition_failure {
    
    my $self = shift;
    
    my $recognizer  = shift;
    my $token_ix    = shift;
    my $tokens      = shift;
    
    my $token = $tokens->[$token_ix];
    
    push @{ $self->{recognition_failures} }, { 
        token               => join(': ', @$token),
        events              => [ $recognizer->events ],
        exhausted           => $recognizer->exhausted,
        latest_earley_set   => $recognizer->latest_earley_set,
        # TODO: stringify progress by converting IDs in to rules/symbols
        progress            => [ $recognizer->progress ],
        terminals_expected  => [ $recognizer->terminals_expected ],
    };
    
    # fix things (that includes do nothing) and return true to continue parsing
    # undef will lead to die()
    return "true";
}


sub parse{

    my $self = shift;
    my $input = shift;
    # TODO: get %$features, split $input, set up $tokens
    
    # init recognition failures
    $self->set_option('recognition_failures', []);
    
    $self->show_option('bnf_tokens');
    $self->show_option('bnf_rules');

    # input can be name/value pair arrayref or a string
    # name/value pair arrayrefs are used as is
    my $tokens;
    if (ref $input eq "ARRAY"){
        $tokens = $input;
        # show options if set
        $self->show_option('rules');
        $self->show_option('symbols');
        $self->show_option('terminals');
        $self->show_option('literals');
        # find ambiguous tokens and disambiguate them by adding rules to the grammar
        if ($self->{ambiguity} eq 'tokens'){
#            say "adding rules for ambiguous_tokens";
            # rules for the ambiguous token must be unique
            my $ambiguous_token_rules = {};
            my $rules_name = ref $self->{options}->{rules};
            # enumerate tokens
            for my $i (0..@$tokens-1){
                my $token = $tokens->[$i];
                # if $token is ambiguous, generate and add rules for it before recognizing
                if (ref $token->[0] eq "ARRAY" ){
                    my $ambiguous_token = $token;
#                    _dump "ambiguous token", $ambiguous_token;
                    # get $ambiguous_token names as an array and a string
                    my @names = map { $_->[0] } @$ambiguous_token; 
                    my $names = join('/', @names);
                    # get $ambiguous_token value 
                    my $value = $ambiguous_token->[0]->[1];
                    # disambiguate $ambiguous_token (well, sort of)
                    my $disambiguated_token = [ $names, $value ];
                    # replace ambiguous token with disambiguated
                    $tokens->[$i] = $disambiguated_token;
                    # generate *unique* rules for the $ambiguous_token
                    $ambiguous_token_rules->{$_}->{$names} = undef for @names;
                }
            }
#            _dump "disambiguated tokens", $tokens; 
            # add %$ambiguous_token_rules as generated
#            _dump "ambiguous token rules", $ambiguous_token_rules;
            if ($rules_name eq "ARRAY"){
                # lhs => [qw{rhs}]
                my @rules = map { [ $_ => [ $ambiguous_token_rules->{$_} ] ] } keys %$ambiguous_token_rules;
                $self->merge_token_rules(\@rules);
            }
            else{
                # make a BNF grammar of @ambiguous_token_rules
                my $bnf = "\n# rules added from ambiguous tokens\n";
                # lhs ::= rhs
                for my $lhs (keys %$ambiguous_token_rules){
                    my @rhs = keys %{ $ambiguous_token_rules->{$lhs} };
                    $bnf .= join "\n", map { $lhs . '::=' . $_ } @rhs;
                    $bnf .= "\n";
                }
                $bnf .= "\n";
                # add $bnf to $self->{options}->{$rules} and rebuild the grammar
                $self->merge_token_rules($bnf);
            }
        } ## ($self->{ambiguity} eq 'tokens'
    } ## if (ref $input eq "ARRAY"){
    # strings are split
    else{
        $tokens = $self->lex($input);
    }

    $self->set_option('tokens', $tokens);
    $self->show_option('tokens');
    
    # get grammar and closures
    my $grammar  = $self->{grammar};
    
    my $closures = $self->{closures};
    
    $self->show_option('closures');

#    say $self->get_option('tokens');
#    say $self->get_option('rules');
#    say $self->get_option('terminals');

    # setup recognizer
    my $recognizer = Marpa::R2::Recognizer->new( { 
        grammar => $grammar, 
        closures => $closures,
#        trace_terminals => 3,
    } ) or die 'Failed to create recognizer';

    # read tokens
    for my $i (0..@$tokens-1){
        my $token = $tokens->[$i];
# _dump "read()ing", $token;
        if (ref $token->[0] eq "ARRAY"){ # ambiguous token
            # use alternate/end_input
            for my $alternative (@$token) {
                my ($name, $value) = @$alternative;
                $recognizer->alternative( $name, \$value, 1 )
            }
            $recognizer->earleme_complete();
        }
        else{ # unambiguous token
               defined $recognizer->read( @$token ) 
            or $self->{recognition_failure_sub}->($self, $recognizer, $i, $tokens) 
            or die "Parse failed";
        }
#        say "# progress:", $recognizer->show_progress;
    }

#    $self->show_option('recognition_failures');
#    $self->show_recognition_failures if $self->{recognition_failures};
    
    # get values    
    my @values;
    my %values; # only unique parses will be returned
    while ( defined( my $value_ref = $recognizer->value() ) ) {
        my $value = $value_ref ? ${$value_ref} : 'No parse';
        # use dumper based on default_action
        my $value_dump = ref $value ? 
            $self->{default_action} eq __PACKAGE__ . '::tree' ?
                $self->show_parse_tree($value, 'text') 
                :
                Dump $value
            :
            $value;
        # TODO: $ebnf_parser produces very ambiguous grammars
        next if exists $values{$value_dump};
        # save unique parses for return
        # prepend xml prolog and encode to utf8 if we need to return an XML string
        if ($self->{default_action} eq __PACKAGE__ . '::xml'){
            $value = '<?xml version="1.0"?>' . "\n" . $value;
            # enforce strict encoding (UTF-8 rather than utf8)
            $value = encode("UTF-8", $value);
        }
        push @values, $value;
        # save parse to test for uniqueness
        $values{$value_dump} = undef;
    }
    # TODO: replace recursion in show_parse_tree with loop
    # $self->{parse_tree} shall always be array 
    $self->{multiple_parse_trees} = scalar @values - 1;
    
    # set up the return value and parse tree reference    
    if (wantarray){         # mupltiple parses are expected
        $self->{parse_tree} = \@values;
        return @values;
    }
    elsif (@values > 1){    # single parse is expected, but we have many, 
        $self->{parse_tree} = \@values;
        return \@values;    # hence the array ref
    }
    else {
        $self->{parse_tree} = $values[0];
        return $values[0];  # single parse is expected and we have just it
                            # hence the scalar
    }
    
}

1;