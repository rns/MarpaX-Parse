Marpa-Easy-proof-of-concept
===========================

This module is an attempt at providing an easy-to-use interface 
to Marpa::R2.

"Easy-to-use" currently means that a user can:

* call `parse` method on the input and receive the value produced by Marpa::R2 evaluator or a  by actions or closures set in `rules`
* use closures (`sub { ... }`) in Marpa::R2::Grammar rules,
* omit default_action and have it set to `'AoA'` to have the rules evaluated to arrays of arrays automagically,
* have the lhs of the first rule passed to Marpa::R2::Grammar set as its start symbol, if no start symbol is set in Marpa::R2::Grammar constructor,
* set the `'rules'` argument of Marpa::R2::Grammar to a string containing a BNF grammar (which may define actions in `%{ %}` tags), 
* have literals extracted and used to lex the input into tokens that will go to the recognizer, 
* set default_action to `'tree'`, `'xml'`, `'sexpr'`, `'AoA'`, and `'HoA'`, to have `parse` return a parse tree (Tree::Simple, XML string, S-expression string, array of arrays, and hash of arrays, accordingly), 
* call `show_parse_tree($format)` to view the parse tree as text dump, HTML or formatted XML;
* use Tree::Simple::traverse, Tree::Simple::Visitor or XML::Twig to traverse the relevant parse trees and gain results.

The input can be a string or a reference to an array of `[ $type, $value ]` refs. 

Ambiguous tokens can be defined by setting the input array item(s) to 
`[ [ $type1, $value ],  [ $type2, $value ] ] ...` and will be handled with 
`alternate()/earleme_complete()` input model.

The test-to-feature mapping is given below.


Transformation of the rules for Marpa::R2::Grammar and extract closures and lexer rules setting the basis for further parsing of BNF to Marpa::R2 rules:

-	[`02_set_start_and_default_action.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/02_set_start_and_default_action.t),
-	[`03_closures_in_rules.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/03_closures_in_rules.t),
-	[`04_lexing_on_terminal_literals.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/04_lexing_on_terminal_literals.t), and
-	[`05_quantified_symbols_sequence.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/05_quantified_symbols_sequence.t)


An example from the Parse::RecDescent tutorial, done the Marpa way:

-	[`06_reversing_diff.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/06_reversing_diff.t)


A BNF grammar with actions that can parse a possible signed decimal number, integer or float:
 
-	[`07_decimal_number_bnf.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/07_decimal_number_bnf.t)


A BNF grammar that can parse a BNF grammar that can parse a decimal number:

-	[`08_bnf_in_bnf.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/08_bnf_in_bnf.t)


An example from the Parse::RecDescent tutorial done in BNF with actions:

-	[`09_reversing_diff_bnf.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/09_reversing_diff_bnf.t)


Parse trees generation and traversal:

-	[`10_parse_tree_simple.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/10_parse_tree_simple.t)

-	[`11_parse_tree_xml.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/11_parse_tree_xml.t)


Comparison of parse tree traversal:

-	[`13_decimal_number_power_expansion_bnf_parse_trees_vs_actions.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/13_decimal_number_power_expansion_bnf_parse_trees_vs_actions.t).



Parsing �time flies like an arrow, bit fruit flies like a banana� sentence getting part of speech data from WordNet::QueryData (if installed) or pre-set hash ref (otherwise).

-	[`15_timeflies_input_model.t`](https://github.com/rns/Marpa-Easy-proof-of-concept/blob/master/t/15_timeflies_input_model.t)

Pre-requisites:

**Core** (closures in rules, terminal-based lexing, quantified symbols, textual BNF with actions, see test cases 02-07, 08 for details)

	Marpa::R2
	Clone
	Eval::Closure
	Math::Combinatorics

**Parse Trees** (set default_action to 'xml', 'tree', 'sexpr' or 'AoA' to have XML string, Tree::Simple, S-expression or array of arrays parse trees accordingly; use show_parse_tree("text" or "html") to view Tree::Simple parse trees as text or html, see test cases 10, 11 and 13 for details))

	Data::TreeDumper
	Tree::Simple
		Tree::Simple::Visitor
		Tree::Simple::View
	XML::Twig

_Optional_, if you need to see how part-of-speech data are pulled from WordNet for text case 15 (�time flies like an arrow, bit fruit flies like a banana�); if WordNet::QueryData is not installed, the pre-pulled data specified in the test script will be used.

	WordNet::QueryData
