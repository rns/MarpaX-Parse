Marpa-Easy-proof-of-concept
===========================

This module is an attempt at providing an easy-to-use interface 
to Marpa::R2.

"Easy-to-use" currently means that a user can set the 'rules' argument 
of Marpa::R2::Grammar to a string containing a BNF grammar (which
may define actions in %{ %} tags), whose literals will be extracted and 
used to lex the input, call parse method on the input and receive 
the value produced by Marpa::R2 evaluator or a parse tree (Tree::Simple, 
XML string, S-expression string, array of arrays, hash of arrays) 
by setting the default_action to 'tree', 'xml', 'sexpr', 'AoA', 
'HoA', accordingly. 

The input can be a string or a reference to an array of [ $type, $value ] refs. 

Ambiguous tokens can be defined by setting the input array item(s) to 
[ [ $type1, $value ],  [ $type2, $value ] ] and will be handled with 
alternate()/earleme_complete().

Below are some of the test cases with brief descriptions.

[01_with_marpa_recognizer.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/01_with_marpa_recognizer.t) -- Marpa::Easy can be used with Marpa::R2::Recognizer

[02_set_start_and_default_action.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/02_set_start_and_default_action.t)

[03_closures_in_rules.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/03_closures_in_rules.t)

[04_lexing_on_terminal_literals.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/04_lexing_on_terminal_literals.t)

[05_quantified_symbols_sequence.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/05_quantified_symbols_sequence.t) -- These transform the rules 
for Marpa::R2::Grammar and extract closures and lexer rules 
setting the basis for further parsing of BNF to Marpa::R2 rules.

[06_reversing_diff.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/06_reversing_diff.t) -- An example from the Parse::RecDescent 
tutorial, done the Marpa way.

[07_decimal_number_bnf.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/07_decimal_number_bnf.t) -- A BNF grammar with actions that can parse a possible signed decimal 
number, integer or float.

[08_bnf_in_bnf.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/08_bnf_in_bnf.t) -- A BNF grammar that can parse a BNF grammar that can parse a decimal number

[09_reversing_diff_bnf.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/09_reversing_diff_bnf.t) -- An example from the Parse::RecDescent 
tutorial done in BNF with actions.

[10_parse_tree_simple.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/10_parse_tree_simple.t)

[11_parse_tree_xml.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/11_parse_tree_xml.t) -- Parse tree examples

[13_decimal_number_power_expansion_bnf_parse_trees_vs_actions.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/13_decimal_number_power_expansion_bnf_parse_trees_vs_actions.t) -- Parse 
tree comparison.

[15_timeflies_input_model.t](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/15_timeflies_input_model.t) -- getting part of speech data from WordNet::QueryData (which is a pre-req) and parsing �time flies like an arrow...� sentence.

Other pre-reqs:

core (closures in rules, terminal-based lexing, quantified symbols, textual BNF with actions, see test cases 02-07, 08 for details)

	Marpa::R2
	Clone
	Eval::Closure
	Math::Combinatorics

parse trees (set default_action to 'xml', 'tree', 'sexpr' or 'AoA' to have XML string, Tree::Simple, S-expression or array of arrays parse trees accordingly; use show_parse_tree("text" or "html") to view Tree::Simple parse trees as text or html, see test cases 10, 11 and 13 for details))

	Data::TreeDumper
	Tree::Simple
		Tree::Simple::Visitor
		Tree::Simple::View
	XML::Twig

optional, if you need to see how part-of-speech data are pulled from WordNet for text case 15 (�time flies like an arrow, bit fruit flies like a banana�); if WordNet::QueryData is not installed, the pre-pulled data specified in the test script will be used.

	WordNet::QueryData
