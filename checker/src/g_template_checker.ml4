(*i camlp4deps: "grammar/grammar.cma" i*)

DECLARE PLUGIN "template_coq_checker"

open Stdarg
open Pp
open PeanoNat.Nat
open Checker0
let pr_char c = str (Char.escaped c)
   
let pr_char_list = prlist_with_sep mt pr_char

let check gr =
  let env = Global.env () in
  let sigma = Evd.from_env env in
  let sigma, c = Evarutil.new_global sigma gr in
  (* Feedback.msg_debug (str"Quoting"); *)
  let term = Term_quoter.quote_term_rec env (EConstr.to_constr sigma c) in
  (* Feedback.msg_debug (str"Finished quoting.. checking."); *)
  let fuel = pow two (pow two (pow two two)) in
  match Checker0.typecheck_program fuel term with
  | CorrectDecl t ->
     Feedback.msg_info (str "Successfully checked of type: " ++ pr_char_list (Checker0.string_of_term t))
  | EnvError (AlreadyDeclared id) ->
     CErrors.user_err ~hdr:"template-coq" (str "Already declared: " ++ pr_char_list id)
  | EnvError (IllFormedDecl (id, e)) ->
     CErrors.user_err ~hdr:"template-coq" (pr_char_list (Checker0.string_of_type_error e) ++ str ", while checking " ++ pr_char_list id)
    
VERNAC COMMAND EXTEND TemplateCheck CLASSIFIED AS QUERY
| [ "Template" "Check" global(gr) ] -> [
    let gr = Nametab.global gr in
    check gr
  ]
END
