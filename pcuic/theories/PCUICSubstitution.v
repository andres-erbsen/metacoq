 (* Distributed under the terms of the MIT license.   *)

(** * Substitution lemmas for typing derivations. *)

From Coq Require Import Bool List Arith Lia.
From MetaCoq.Template Require Import utils config.
From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICInduction
  PCUICLiftSubst PCUICEquality PCUICPosition PCUICSigmaCalculus
  PCUICUnivSubst PCUICTyping PCUICWeakeningEnv PCUICClosed
  PCUICReduction PCUICWeakening PCUICUnivSubstitution.
Require Import ssreflect.

From Equations Require Import Equations.

Set Asymmetric Patterns.
Local Set Keyed Unification.
Close Scope string_scope.

Set Default Goal Selector "!".

Hint Rewrite @app_context_length : wf.

Generalizable Variables Σ Γ t T.

(** Well-typed substitution into a context with *no* let-ins *)

Inductive subs {cf:checker_flags} (Σ : global_env_ext) (Γ : context) : list term -> context -> Type :=
| emptys : subs Σ Γ [] []
| cons_ass Δ s na t T : subs Σ Γ s Δ -> Σ ;;; Γ |- t : subst0 s T -> subs Σ Γ (t :: s) (Δ ,, vass na T).

(** Linking a context (with let-ins), an instance (reversed substitution)
    for its assumptions and a well-formed substitution for it. *)

Inductive context_subst : context -> list term -> list term -> Type :=
| context_subst_nil : context_subst [] [] []
| context_subst_ass Γ args s na t a :
    context_subst Γ args s ->
    context_subst (vass na t :: Γ) (args ++ [a]) (a :: s)
| context_subst_def Γ args s na b t :
    context_subst Γ args s ->
    context_subst (vdef na b t :: Γ) args (subst s 0 b :: s).

(** Promoting a substitution for the non-let declarations of ctx into a
    substitution for the whole context *)

Fixpoint make_context_subst ctx args s :=
  match ctx with
  | [] => match args with
          | [] => Some s
          | a :: args => None
          end
  | d :: ctx =>
    match d.(decl_body) with
    | Some body => make_context_subst ctx args (subst0 s body :: s)
    | None => match args with
              | a :: args => make_context_subst ctx args (a :: s)
              | [] => None
              end
    end
  end.

(** Well-typed substitution into a context with let-ins *)

Inductive subslet {cf:checker_flags} Σ (Γ : context) : list term -> context -> Type :=
| emptyslet : subslet Σ Γ [] []
| cons_let_ass Δ s na t T : subslet Σ Γ s Δ ->
              Σ ;;; Γ |- t : subst0 s T ->
             subslet Σ Γ (t :: s) (Δ ,, vass na T)
| cons_let_def Δ s na t T :
    subslet Σ Γ s Δ ->
    Σ ;;; Γ |- subst0 s t : subst0 s T ->
    subslet Σ Γ (subst0 s t :: s) (Δ ,, vdef na t T).

Lemma subslet_nth_error {cf:checker_flags} Σ Γ s Δ decl n t :
  subslet Σ Γ s Δ ->
  nth_error Δ n = Some decl ->
  nth_error s n = Some t ->
  match decl_body decl return Type with
  | Some t' =>
    let b := subst0 (skipn (S n) s) t' in
    let ty := subst0 (skipn (S n) s) (decl_type decl) in
    ((t = b) * (Σ ;;; Γ |- b : ty))%type
  | None =>
    let ty := subst0 (skipn (S n) s) (decl_type decl) in
    Σ ;;; Γ |- t : ty
  end.
Proof.
  induction 1 in n |- *; simpl; auto; destruct n; simpl; try congruence.
  - intros [= <-]. intros [= ->].
    simpl. exact t1.
  - intros. destruct decl as [na' [b|] ty]; cbn in *.
    + specialize (IHX _ H H0). intuition auto.
    + now apply IHX.
  - intros [= <-]. intros [= <-].
    simpl. split; auto.
  - apply IHX.
Qed.

Lemma subslet_length {cf:checker_flags} {Σ Γ s Δ} : subslet Σ Γ s Δ -> #|s| = #|Δ|.
Proof.
  induction 1; simpl; auto with arith.
Qed.

Lemma subst_decl_closed n k d : closed_decl k d -> subst_decl n k d = d.
Proof.
  case: d => na [body|] ty; rewrite /closed_decl /subst_decl /map_decl /=.
  - move/andP => [cb cty]. rewrite !subst_closedn //.
  - move=> cty; now rewrite !subst_closedn //.
Qed.

Lemma closed_ctx_subst n k ctx : closed_ctx ctx = true -> subst_context n k ctx = ctx.
Proof.
  induction ctx in n, k |- *; auto.
  unfold closed_ctx, id.
  rewrite mapi_app forallb_app List.rev_length /= Nat.add_0_r.
  move/andb_and => /= [Hctx /andb_and [Ha _]].
  rewrite subst_context_snoc /snoc /= IHctx // subst_decl_closed //.
  now apply: closed_decl_upwards.
Qed.

Lemma closed_tele_subst n k ctx :
  closed_ctx ctx ->
  mapi (fun (k' : nat) (decl : context_decl) => subst_decl n (k' + k) decl) (List.rev ctx) = List.rev ctx.
Proof.
  rewrite /closedn_ctx /mapi. simpl. generalize 0.
  induction ctx using rev_ind; try easy.
  move=> n0.
  rewrite /closedn_ctx !rev_app_distr /id /=.
  move/andP => [closedx Hctx].
  rewrite subst_decl_closed //.
  - rewrite (closed_decl_upwards n0) //; lia.
  - f_equal. now rewrite IHctx.
Qed.

Lemma map_vass_map_def_subst g l n k :
  (mapi (fun i (d : def term) => vass (dname d) (lift0 i (dtype d)))
        (map (map_def (subst n k) g) l)) =
  (mapi (fun i d => map_decl (subst n (i + k)) d) (mapi (fun i (d : def term) => vass (dname d) (lift0 i (dtype d))) l)).
Proof.
  rewrite mapi_mapi mapi_map. apply mapi_ext.
  intros. unfold map_decl, vass; simpl; f_equal.
  rewrite commut_lift_subst_rec. 1: lia. f_equal; lia.
Qed.

Lemma All_local_env_subst {cf:checker_flags} (P Q : context -> term -> option term -> Type) c n k :
  All_local_env Q c ->
  (forall Γ t T,
      Q Γ t T ->
      P (subst_context n k Γ) (subst n (#|Γ| + k) t)
        (option_map (subst n (#|Γ| + k)) T)
  ) ->
  All_local_env P (subst_context n k c).
Proof.
  intros Hq Hf.
  induction Hq in |- *; try econstructor; eauto;
    simpl; unfold snoc; rewrite subst_context_snoc; econstructor; eauto.
  - simpl. eapply (Hf _ _ None). eauto.
  - simpl. eapply (Hf _ _ None). eauto.
  - simpl. eapply (Hf _ _ (Some t)). eauto.
Qed.

Lemma subst_length {cf:checker_flags} Σ Γ s Γ' : subs Σ Γ s Γ' -> #|s| = #|Γ'|.
Proof.
  induction 1; simpl; auto with arith.
Qed.

Lemma subs_nth_error_ge {cf:checker_flags} Σ Γ Γ' Γ'' v s :
  subs Σ Γ s Γ' ->
  #|Γ' ,,, Γ''| <= v ->
  nth_error (Γ ,,, Γ' ,,, Γ'') v =
  nth_error (Γ ,,, subst_context s 0 Γ'') (v - #|Γ'|).
Proof.
  simpl.
  intros. rewrite app_context_length in H.
  rewrite !nth_error_app_ge; autorewrite with wf; f_equal; try lia.
Qed.

Lemma nth_error_subst_context (Γ' : context) s (v : nat) k :
    nth_error (subst_context s k Γ') v =
    option_map (subst_decl s (#|Γ'| - S v + k)) (nth_error Γ' v).
Proof.
  induction Γ' in v |- *; intros.
  - simpl. unfold subst_context, fold_context; simpl; rewrite nth_error_nil. easy.
  - simpl. destruct v; rewrite subst_context_snoc.
    + simpl. repeat f_equal; try lia.
    + simpl. rewrite IHΓ'; simpl in *; (lia || congruence).
Qed.

Lemma subs_nth_error_lt {cf:checker_flags} Σ Γ Γ' Γ'' v s :
  subs Σ Γ s Γ' ->
  v < #|Γ''| ->
  nth_error (Γ ,,, subst_context s 0 Γ'') v =
  option_map (map_decl (subst s (#|Γ''| - S v))) (nth_error (Γ ,,, Γ' ,,, Γ'') v).
Proof.
  simpl. intros Hs Hv.
  rewrite !nth_error_app_lt; autorewrite with wf; f_equal; try lia.
  erewrite nth_error_subst_context. f_equal. unfold subst_decl. rewrite Nat.add_0_r. reflexivity.
Qed.

Lemma subslet_nth_error_lt {cf:checker_flags} Σ Γ Γ' Γ'' v s :
  subslet Σ Γ s Γ' ->
  v < #|Γ''| ->
  nth_error (Γ ,,, subst_context s 0 Γ'') v =
  option_map (map_decl (subst s (#|Γ''| - S v))) (nth_error (Γ ,,, Γ' ,,, Γ'') v).
Proof.
  simpl. intros Hs Hv.
  rewrite !nth_error_app_lt; autorewrite with wf; f_equal; try lia.
  erewrite nth_error_subst_context. f_equal. unfold subst_decl. rewrite Nat.add_0_r. reflexivity.
Qed.

Lemma subst_iota_red s k pars c args brs :
  subst s k (iota_red pars c args brs) =
  iota_red pars c (List.map (subst s k) args) (List.map (on_snd (subst s k)) brs).
Proof.
  unfold iota_red. rewrite !subst_mkApps. f_equal; auto using map_skipn.
  rewrite nth_map; simpl; auto.
Qed.

Lemma subst_unfold_fix n k mfix idx narg fn :
  unfold_fix mfix idx = Some (narg, fn) ->
  unfold_fix (map (map_def (subst n k) (subst n (#|mfix| + k))) mfix) idx = Some (narg, subst n k fn).
Proof.
  unfold unfold_fix.
  rewrite nth_error_map. destruct (nth_error mfix idx) eqn:Hdef; try congruence.
  move=> [= <- <-] /=. f_equal. f_equal.
  solve_all.
  erewrite (distr_subst_rec _ _ _ k 0).
  rewrite fix_subst_length. simpl. f_equal.
  unfold fix_subst. rewrite !map_length.
  generalize #|mfix| at 2 3. induction n0; auto. simpl.
  f_equal. apply IHn0.
Qed.
Hint Resolve subst_unfold_fix : core.

Lemma subst_unfold_cofix n k mfix idx narg fn :
  unfold_cofix mfix idx = Some (narg, fn) ->
  unfold_cofix (map (map_def (subst n k) (subst n (#|mfix| + k))) mfix) idx = Some (narg, subst n k fn).
Proof.
  unfold unfold_cofix.
  rewrite nth_error_map. destruct (nth_error mfix idx) eqn:Hdef; try congruence.
  intros [= <- <-]. simpl. do 2 f_equal. solve_all.
  erewrite (distr_subst_rec _ _ _ k 0).
  rewrite cofix_subst_length. simpl. f_equal.
  unfold cofix_subst. rewrite !map_length.
  generalize #|mfix| at 2 3. induction n0; auto. simpl.
  f_equal. apply IHn0.
Qed.
Hint Resolve subst_unfold_cofix : core.

Lemma decompose_app_rec_subst n k t l :
  let (f, a) := decompose_app_rec t l in
  subst n k f = f ->
  decompose_app_rec (subst n k t) (map (subst n k) l)  = (f, map (subst n k) a).
Proof.
  induction t in k, l |- *; simpl; auto; try congruence.

  - destruct Nat.leb; try reflexivity.
    destruct nth_error.
    + simpl. intros ->. simpl. reflexivity.
    + intros ->. simpl. reflexivity.
  - specialize (IHt1 k (t2 :: l)).
    destruct decompose_app_rec. intros H. rewrite IHt1; auto.
Qed.

Lemma decompose_app_subst n k t f a :
  decompose_app t = (f, a) -> subst n k f = f ->
  decompose_app (subst n k t) = (subst n k f, map (subst n k) a).
Proof.
  generalize (decompose_app_rec_subst n k t []).
  unfold decompose_app. destruct decompose_app_rec.
  move=> Heq [= <- <-] Heq'. now rewrite Heq' (Heq Heq').
Qed.
Hint Rewrite decompose_app_subst using auto : lift.

Lemma subst_is_constructor:
  forall (args : list term) (narg : nat) n k,
    is_constructor narg args = true -> is_constructor narg (map (subst n k) args) = true.
Proof.
  intros args narg.
  unfold is_constructor; intros.
  rewrite nth_error_map. destruct nth_error; try discriminate. simpl. intros.
  unfold isConstruct_app in *.
  destruct (decompose_app t) eqn:Heq. eapply decompose_app_subst in Heq as ->.
  - destruct t0; try discriminate || reflexivity.
  - destruct t0; try discriminate || reflexivity.
Qed.
Hint Resolve subst_is_constructor : core.
Hint Constructors All_local_env : core.

Lemma typed_subst `{checker_flags} Σ Γ t T n k :
  wf Σ.1 -> k >= #|Γ| ->
  Σ ;;; Γ |- t : T -> subst n k T = T /\ subst n k t = t.
Proof.
  intros wfΣ Hk Hty.
  pose proof (typing_wf_local Hty).
  apply typecheck_closed in Hty; eauto.
  destruct Hty as [_ Hcl].
  rewrite -> andb_and in Hcl. destruct Hcl as [clb clty].
  pose proof (closed_upwards k clb).
  simpl in *. forward H0 by lia.
  pose proof (closed_upwards k clty).
  simpl in *. forward H1 by lia.
  apply (subst_closedn n) in H0; apply (subst_closedn n) in H1; auto.
Qed.

Lemma subst_wf_local `{checker_flags} Σ Γ n k :
  wf Σ.1 ->
  wf_local Σ Γ ->
  subst_context n k Γ = Γ.
Proof.
  intros wfΣ.
  induction 1; auto; unfold subst_context, snoc; rewrite fold_context_snoc0;
    auto; unfold snoc;
    f_equal; auto; unfold map_decl; simpl.
  - destruct t0 as [s Hs]. unfold vass. simpl. f_equal.
    eapply typed_subst; eauto. lia.
  - unfold vdef.
    f_equal.
    + f_equal. eapply typed_subst; eauto. lia.
    + eapply typed_subst in t1 as [Ht HT]; eauto. lia.
Qed.

Lemma subst_declared_constant `{H:checker_flags} Σ cst decl n k u :
  wf Σ ->
  declared_constant Σ cst decl ->
  map_constant_body (subst n k) (map_constant_body (subst_instance_constr u) decl) =
  map_constant_body (subst_instance_constr u) decl.
Proof.
  intros.
  eapply declared_decl_closed in H0; eauto.
  unfold map_constant_body.
  do 2 red in H0. destruct decl as [ty [body|] univs]; simpl in *.
  - rewrite -> andb_and in H0. intuition.
    rewrite <- (closedn_subst_instance_constr 0 body u) in H1.
    rewrite <- (closedn_subst_instance_constr 0 ty u) in H2.
    f_equal.
    + apply subst_closedn; eauto using closed_upwards with arith wf.
    + f_equal. apply subst_closedn; eauto using closed_upwards with arith wf.
  - red in H0. f_equal.
    intuition. simpl in *.
    rewrite <- (closedn_subst_instance_constr 0 ty u) in H0.
    rewrite andb_true_r in H0.
    eapply subst_closedn; eauto using closed_upwards with arith wf.
Qed.

Definition subst_mutual_inductive_body n k m :=
  map_mutual_inductive_body (fun k' => subst n (k' + k)) m.

Lemma subst_declared_minductive {cf:checker_flags} Σ cst decl n k :
  wf Σ ->
  declared_minductive Σ cst decl ->
  subst_mutual_inductive_body n k decl = decl.
Proof.
  intros wfΣ Hdecl.
  pose proof (on_declared_minductive wfΣ Hdecl). apply onNpars in X.
  apply (declared_inductive_closed (Σ:=(empty_ext Σ))) in Hdecl; auto.
  move: Hdecl.
  rewrite /closed_inductive_decl /lift_mutual_inductive_body.
  destruct decl; simpl.
  move/andP => [clpar clbodies]. f_equal.
  - now rewrite [fold_context _ _]closed_ctx_subst.
  - eapply forallb_All in clbodies.
    eapply Alli_mapi_id.
    * eapply (All_Alli clbodies). intros; eauto.
      intros. eapply H.
    * simpl; intros.
      move: H. rewrite /closed_inductive_body.
      destruct x; simpl. move=> /andP[/andP [ci ct] cp].
      f_equal. 
      + rewrite subst_closedn; eauto.
        eapply closed_upwards; eauto; lia.
      + eapply All_map_id. eapply forallb_All in ct.
        eapply (All_impl ct). intros x.
        destruct x as [[id ty] arg]; unfold on_pi2; intros c; simpl; repeat f_equal.
        apply subst_closedn. unfold cdecl_type in c; simpl in c.
        eapply closed_upwards; eauto; lia.
      + simpl in X. rewrite -X in cp.
        eapply forallb_All in cp. eapply All_map_id; eauto.
        eapply (All_impl cp); firstorder auto.
        destruct x; unfold on_snd; simpl; f_equal.
        apply subst_closedn. rewrite context_assumptions_fold.
        eapply closed_upwards; eauto; lia.
Qed.

Lemma subst_declared_inductive {cf:checker_flags} Σ ind mdecl idecl n k :
  wf Σ ->
  declared_inductive Σ mdecl ind idecl ->
  map_one_inductive_body (context_assumptions mdecl.(ind_params))
                         (length (arities_context mdecl.(ind_bodies)))
                         (fun k' => subst n (k' + k)) (inductive_ind ind) idecl = idecl.
Proof.
  unfold declared_inductive. intros wfΣ [Hmdecl Hidecl].
   eapply (subst_declared_minductive _ _ _ n k) in Hmdecl. 2: auto.
  unfold subst_mutual_inductive_body in Hmdecl.
  destruct mdecl. simpl in *.
  injection Hmdecl. intros Heq.
  clear Hmdecl.
  pose proof Hidecl as Hidecl'.
  rewrite <- Heq in Hidecl'.
  rewrite nth_error_mapi in Hidecl'.
  clear Heq.
  unfold option_map in Hidecl'. rewrite Hidecl in Hidecl'.
  congruence.
Qed.

Lemma subst0_inds_subst ind u mdecl n k t :
  (subst0 (inds (inductive_mind ind) u (ind_bodies mdecl))
          (subst n (#|arities_context (ind_bodies mdecl)| + k) t)) =
  subst n k (subst0 (inds (inductive_mind ind) u (ind_bodies mdecl)) t).
Proof.
  pose proof (distr_subst_rec t (inds (inductive_mind ind) u (ind_bodies mdecl)) n k 0).
  simpl in H. rewrite H.
  unfold arities_context. rewrite rev_map_length inds_length.
  f_equal. generalize (ind_bodies mdecl).
  clear. intros.
  induction l; unfold inds; simpl; auto. f_equal. auto.
Qed.

Lemma subst_declared_constructor {cf:checker_flags} Σ c u mdecl idecl cdecl n k :
  wf Σ -> declared_constructor Σ mdecl idecl c cdecl ->
  subst (map (subst_instance_constr u) n) k (type_of_constructor mdecl cdecl c u) = (type_of_constructor mdecl cdecl c u).
Proof.
  unfold declared_constructor. destruct c as [i ci]. intros wfΣ [Hidecl Hcdecl].
  eapply (subst_declared_inductive _ _ _ _ n k) in Hidecl; eauto.
  unfold type_of_constructor. destruct cdecl as [[id t'] arity].
  destruct idecl; simpl in *.
  injection Hidecl. intros.
  pose Hcdecl as Hcdecl'.
  rewrite <- H0 in Hcdecl'.
  rewrite nth_error_map in Hcdecl'. rewrite Hcdecl in Hcdecl'.
  simpl in Hcdecl'. injection Hcdecl'.
  intros.
  rewrite <- H2 at 2.
  rewrite <- subst0_inds_subst. f_equal.
  now rewrite <- subst_subst_instance_constr.
Qed.

Lemma subst_declared_projection {cf:checker_flags} Σ c mdecl idecl pdecl n k :
  wf Σ ->
  declared_projection Σ mdecl idecl c pdecl ->
  on_snd (subst n (S (ind_npars mdecl + k))) pdecl = pdecl.
Proof.
  intros.
  eapply (declared_projection_closed (Σ:=empty_ext Σ)) in H; auto.
  unfold on_snd. simpl.
  rewrite subst_closedn. 
  - eapply closed_upwards; eauto; try lia.
  - destruct pdecl; reflexivity.
Qed.  

Lemma subst_fix_context:
  forall (mfix : list (def term)) n (k : nat),
    fix_context (map (map_def (subst n k) (subst n (#|mfix| + k))) mfix) =
    subst_context n k (fix_context mfix).
Proof.
  intros mfix n k. unfold fix_context.
  rewrite map_vass_map_def_subst rev_mapi.
  fold (fix_context mfix).
  rewrite (subst_context_alt n k (fix_context mfix)).
   now rewrite /subst_decl mapi_length fix_context_length.
Qed.

Lemma subst_destArity ctx t n k :
  match destArity ctx t with
  | Some (args, s) =>
    destArity (subst_context n k ctx) (subst n (#|ctx| + k) t) = Some (subst_context n k args, s)
  | None => True
  end.
Proof.
  revert ctx.
  induction t in n, k |- * using term_forall_list_ind; intros ctx; simpl; trivial.
  - move: (IHt2 n k (ctx,, vass n0 t1)).
    now rewrite subst_context_snoc /= /subst_decl /map_decl /vass /=.
  - move: (IHt3 n k (ctx,, vdef n0 t1 t2)).
    now rewrite subst_context_snoc /= /subst_decl /map_decl /vass /=.
Qed.

Lemma decompose_prod_n_assum0 ctx t : decompose_prod_n_assum ctx 0 t = Some (ctx, t).
Proof. destruct t; simpl; reflexivity. Qed.

Lemma subst_instantiate_params_subst n k params args s t :
  forall s' t',
    instantiate_params_subst params args s t = Some (s', t') ->
    instantiate_params_subst
      (mapi_rec (fun k' decl => subst_decl n (k' + k) decl) params #|s|)
      (map (subst n k) args) (map (subst n k) s) (subst n (#|s| + k) t) =
    Some (map (subst n k) s', subst n (#|s| + k + #|params|) t').
Proof.
  induction params in args, t, n, k, s |- *; intros ctx' t'.
  - destruct args; simpl; rewrite ?Nat.add_0_r; try congruence.
  - simpl.
    destruct a as [na [body|] ty]; simpl; try congruence;
    destruct t; try congruence.
    -- intros Ht'.
       specialize (IHparams n k _ _ _ _ _ Ht').
       simpl in IHparams.
       replace (#|s| + k + S #|params|) with (S (#|s| + k + #|params|)) by lia.
       rewrite <- IHparams. f_equal.
       now rewrite distr_subst.
    -- intros Ht'. destruct args; try congruence. simpl.
       specialize (IHparams n k _ _ _ _ _ Ht').
       simpl in IHparams.
       replace (#|s| + k + S #|params|) with (S (#|s| + k + #|params|)) by lia.
       now rewrite <- IHparams.
Qed.

Lemma decompose_prod_n_assum_extend_ctx {ctx n t ctx' t'} ctx'' :
  decompose_prod_n_assum ctx n t = Some (ctx', t') ->
  decompose_prod_n_assum (ctx ++ ctx'') n t = Some (ctx' ++ ctx'', t').
Proof.
  induction n in ctx, t, ctx', t', ctx'' |- *.
  - simpl. intros [= -> ->]. eauto.
  - simpl.
    destruct t; simpl; try congruence.
    + intros H. eapply (IHn _ _ _ _ ctx'' H).
    + intros H. eapply (IHn _ _ _ _ ctx'' H).
Qed.

Lemma subst_it_mkProd_or_LetIn n k ctx t :
  subst n k (it_mkProd_or_LetIn ctx t) =
  it_mkProd_or_LetIn (subst_context n k ctx) (subst n (length ctx + k) t).
Proof.
  induction ctx in n, k, t |- *; simpl; try congruence.
  pose (subst_context_snoc n k ctx a). unfold snoc in e. rewrite e. clear e.
  simpl. rewrite -> IHctx.
  pose (subst_context_snoc n k ctx a). simpl. now destruct a as [na [b|] ty].
Qed.

Lemma to_extended_list_k_subst n k c k' :
  to_extended_list_k (subst_context n k c) k' = to_extended_list_k c k'.
Proof.
  unfold to_extended_list_k. revert k'.
  unf_term. generalize (nil term) at 1 2.
  induction c in n, k |- *; simpl; intros. 1: reflexivity.
  rewrite subst_context_snoc. unfold snoc. simpl.
  destruct a. destruct decl_body.
  - unfold subst_decl, map_decl. simpl.
    now rewrite IHc.
  - simpl. apply IHc.
Qed.

Lemma to_extended_list_k_map_subst:
  forall n (k : nat) (c : context) k',
    #|c| + k' <= k ->
    to_extended_list_k c k' = map (subst n k) (to_extended_list_k c k').
Proof.
  intros n k c k'.
  pose proof (to_extended_list_k_spec c k').
  symmetry. solve_all.
  destruct H as [x' [-> Hx']]. intuition. simpl.
  destruct (leb_spec_Set k x').
  - lia.
  - reflexivity.
Qed.

Lemma subst_instantiate_params n k params args t ty :
  closed_ctx params ->
  instantiate_params params args t = Some ty ->
  instantiate_params params (map (subst n k) args) (subst n k t) = Some (subst n k ty).
Proof.
  unfold instantiate_params.
  move/(closed_tele_subst n k params)=> Heq.
  rewrite -{2}Heq //.
  specialize (subst_instantiate_params_subst n k (List.rev params) args [] t).
  move=> /= Heq'.
  case E: (instantiate_params_subst (List.rev params) args)=> /= [[l' t']|] /= //.
  specialize (Heq' _ _ E). rewrite Heq'. move=> [= <-]. f_equal.
  rewrite distr_subst //.
  move/instantiate_params_subst_length: E => -> /=. do 2 f_equal. lia.
Qed.
Hint Rewrite subst_instantiate_params : lift.

Lemma wf_arities_context' {cf:checker_flags}:
  forall (Σ : global_env_ext) mind (mdecl : mutual_inductive_body),
    wf Σ ->
    on_inductive (lift_typing typing) Σ mind mdecl ->
    wf_local Σ (arities_context (ind_bodies mdecl)).
Proof.
  intros Σ mind mdecl wfΣ Hdecl.
  apply onInductives in Hdecl.
  unfold arities_context.
  revert Hdecl.
  induction (ind_bodies mdecl) using rev_ind. 1: constructor.
  intros Ha.
  rewrite rev_map_app.
  simpl. apply Alli_app in Ha as [Hl Hx].
  inv Hx. clear X0.
  apply onArity in X as [s Hs].
  specialize (IHl Hl).
  econstructor; eauto.
  fold (arities_context l) in *.
  unshelve epose proof (weakening Σ [] (arities_context l) _ _ wfΣ _ Hs).
  1: now rewrite app_context_nil_l.
  simpl in X.
  eapply (env_prop_typing _ _ typecheck_closed) in Hs; eauto.
  rewrite -> andb_and in Hs. destruct Hs as [Hs Ht].
  simpl in Hs. apply (lift_closed #|arities_context l|) in Hs.
  rewrite -> Hs, app_context_nil_l in X. simpl. exists s.
  apply X.
Qed.

Lemma wf_arities_context {cf:checker_flags}  Σ mind mdecl : wf Σ ->
  declared_minductive Σ mind mdecl -> wf_local (Σ, ind_universes mdecl) (arities_context mdecl.(ind_bodies)).
Proof.
  intros wfΣ Hdecl.
  eapply declared_minductive_inv in Hdecl. 2:apply weaken_env_prop_typing. all:eauto.
  eapply wf_arities_context'; eauto.
Qed.

Lemma on_constructor_closed {cf:checker_flags}  {Σ mind mdecl u idecl indices cdecl cs} :
  wf Σ ->
  on_constructor (lift_typing typing) (Σ, ind_universes mdecl) mdecl (inductive_ind mind) indices idecl cdecl cs ->
  let cty := subst0 (inds (inductive_mind mind) u (ind_bodies mdecl))
                    (subst_instance_constr u (snd (fst cdecl)))
  in closed cty.
Proof.
  intros wfΣ [? ? ? [s Hs] Hparams].
  pose proof (typing_wf_local Hs).
  destruct cdecl as [[id cty] car].
  apply subject_closed in Hs; eauto.
  rewrite arities_context_length in Hs.
  simpl in *.
  eapply (closedn_subst _ 0 0).
  - clear. unfold inds.
    induction #|ind_bodies mdecl|; simpl; try constructor; auto.
  - simpl. now rewrite -> inds_length, closedn_subst_instance_constr.
Qed.

Lemma context_subst_length Γ a s : context_subst Γ a s -> #|Γ| = #|s|.
Proof. induction 1; simpl; congruence. Qed.

Lemma context_subst_assumptions_length Γ a s : context_subst Γ a s -> context_assumptions Γ = #|a|.
Proof. induction 1; simpl; try congruence. rewrite app_length /=. lia. Qed.

(* Lemma context_subst_app {cf:checker_flags} Γ Γ' a s : *)
(*   context_subst (Γ' ++ Γ) a s -> *)
(*   { a0 & { a1 & { s0 & { s1 & (context_subst Γ a0 s0 * context_subst (subst_context s0 0 Γ') a1 s1 *)
(*                                * (a = a0 ++ a1) * (s = s1 ++ s0))%type } } } }. *)
(* Proof. *)
(*   induction Γ' in Γ, a, s |- *. simpl. *)
(*   exists a, [], s, []. rewrite app_nil_r; intuition. constructor. *)

(*   simpl. intros Hs. *)
(*   inv Hs. *)
(*   - specialize (IHΓ' _ _ _ H). *)
(*     destruct IHΓ' as (a0' & a1' & s1 & s2 & ((sa0 & sa1) & eqargs) & eqs0). *)
(*     subst. exists a0', (a1' ++ [a1]), s1, (a1 :: s2). intuition eauto. *)
(*     rewrite subst_context_snoc. constructor. auto. now rewrite app_assoc. *)
(*   - specialize (IHΓ' _ _ _ H). *)
(*     destruct IHΓ' as (a0' & a1' & s1 & s2 & ((sa0 & sa1) & eqargs) & eqs0). *)
(*     subst. exists a0', a1', s1, (subst s2 0 (subst s1 #|Γ'| b) :: s2). intuition eauto. *)
(*     rewrite -> subst_context_snoc, Nat.add_0_r. *)
(*     unfold subst_decl; simpl. unfold map_decl. simpl. *)
(*     econstructor. auto. simpl. f_equal. *)
(*     rewrite -> subst_app_simpl; auto. simpl. *)
(*     pose proof(context_subst_length _ _ _ sa1) as Hs1. *)
(*     rewrite subst_context_length in Hs1. rewrite -> Hs1. auto. *)
(* Qed. *)

Lemma make_context_subst_rec_spec ctx args s tele args' s' :
  context_subst ctx args s ->
  make_context_subst tele args' s = Some s' ->
  context_subst (List.rev tele ++ ctx) (args ++ args') s'.
Proof.
  induction tele in ctx, args, s, args', s' |- *.
  - move=> /= Hc. case: args'.
    + move => [= <-].
      now rewrite app_nil_r.
    + move=> a l //.
  - move=> Hc /=. case: a => [na [body|] ty] /=.
    -- specialize (IHtele (vdef na body ty :: ctx) args (subst0 s body :: s) args' s').
       move=> /=. rewrite <- app_assoc.
       move/(IHtele _). move=> H /=. apply H.
       constructor. auto.
    -- case: args' => [|a args']; try congruence.
       specialize (IHtele (vass na ty :: ctx) (args ++ [a]) (a :: s) args' s').
       move=> /=. rewrite <- app_assoc.
       move/(IHtele _). move=> H /=. simpl in H. rewrite <- app_assoc in H. apply H.
       constructor. auto.
Qed.

Lemma make_context_subst_spec tele args s' :
  make_context_subst tele args [] = Some s' ->
  context_subst (List.rev tele) args s'.
Proof.
  move/(make_context_subst_rec_spec [] [] [] _ _ _ context_subst_nil).
  rewrite app_nil_r /= //.
Qed.

Lemma subst_telescope_cons s k d Γ : 
  subst_telescope s k (d :: Γ) = 
  map_decl (subst s k) d :: subst_telescope s (S k) Γ.
Proof.
  simpl. 
  unfold subst_telescope, mapi. simpl.
  rewrite Nat.add_0_r; f_equal.
  rewrite mapi_rec_Sk. apply mapi_rec_ext.
  intros. simpl. now rewrite Nat.add_succ_r.
Qed.

Lemma subst_telescope_comm_rec s k s' k' Γ:
  subst_telescope (map (subst s' k) s) k' (subst_telescope s' (#|s| + k' + k) Γ) =
  subst_telescope s' (k' + k) (subst_telescope s k' Γ).
Proof.
  induction Γ in k, k' |- *; rewrite ?subst_telescope_cons; simpl; auto.
  f_equal.
  * unfold map_decl. simpl.
    f_equal.
    + destruct a as [na [b|] ty]; simpl; auto.
      f_equal. now rewrite distr_subst_rec.
    + now rewrite distr_subst_rec.
  * specialize (IHΓ k (S k')). now rewrite Nat.add_succ_r in IHΓ.
Qed.

Lemma subst_telescope_comm s k s' Γ:
  subst_telescope (map (subst s' k) s) 0 (subst_telescope s' (#|s| + k) Γ) =
  subst_telescope s' k (subst_telescope s 0 Γ).
Proof.
  now rewrite -(subst_telescope_comm_rec _ _ _ 0) Nat.add_0_r.
Qed.

Lemma instantiate_params_subst_make_context_subst ctx args s ty s' ty' :
  instantiate_params_subst ctx args s ty = Some (s', ty') ->
  ∑ ctx'',
  make_context_subst ctx args s = Some s' /\
  decompose_prod_n_assum [] (length ctx) ty = Some (ctx'', ty').
Proof.
  induction ctx in args, s, ty, s' |- *; simpl.
  - case: args => [|a args'] // [= <- <-]. exists []; intuition congruence.
  - case: a => [na [body|] ty''] /=.
    + destruct ty; try congruence.
      intros. move: (IHctx _ _ _ _ H) => [ctx'' [Hmake Hdecomp]].
      eapply (decompose_prod_n_assum_extend_ctx [vdef na0 ty1 ty2]) in Hdecomp.
      unfold snoc. eexists; intuition eauto.
    + destruct ty; try congruence.
      case: args => [|a args']; try congruence.
      move=> H. move: (IHctx _ _ _ _ H) => [ctx'' [Hmake Hdecomp]].
      eapply (decompose_prod_n_assum_extend_ctx [vass na0 ty1]) in Hdecomp.
      unfold snoc. eexists; intuition eauto.
Qed.

Lemma instantiate_params_make_context_subst ctx args ty ty' :
  instantiate_params ctx args ty = Some ty' ->
  ∑ ctx' ty'' s',
    decompose_prod_n_assum [] (length ctx) ty = Some (ctx', ty'') /\
    make_context_subst (List.rev ctx) args [] = Some s' /\ ty' = subst0 s' ty''.
Proof.
  unfold instantiate_params.
  case E: instantiate_params_subst => // [[s ty'']].
  move=> [= <-].
  eapply instantiate_params_subst_make_context_subst in E.
  destruct E as [ctx'' [Hs Hty'']].
  exists ctx'', ty'', s. split; auto.
  now rewrite -> List.rev_length in Hty''.
Qed.

Lemma subst_cstr_concl_head ind u mdecl (arity : context) args :
  let head := tRel (#|ind_bodies mdecl| - S (inductive_ind ind) + #|ind_params mdecl| + #|arity|) in
  let s := (inds (inductive_mind ind) u (ind_bodies mdecl)) in
  inductive_ind ind < #|ind_bodies mdecl| ->
  subst s (#|arity| + #|ind_params mdecl|)
        (subst_instance_constr u (mkApps head (to_extended_list_k (ind_params mdecl) #|arity| ++ args)))
  = mkApps (tInd ind u) (to_extended_list_k (ind_params mdecl) #|arity| ++
                        map (subst s (#|arity| + #|ind_params mdecl|)) (map (subst_instance_constr u) args)).
Proof.
  intros.
  rewrite subst_instance_constr_mkApps subst_mkApps.
  f_equal.
  - subst head. simpl subst_instance_constr.
    rewrite (subst_rel_eq _ _ (#|ind_bodies mdecl| - S (inductive_ind ind)) (tInd ind u)) //; try lia.
    subst s. rewrite inds_spec rev_mapi nth_error_mapi /=.
    elim nth_error_spec.
    + intros. simpl.
      f_equal. destruct ind; simpl. f_equal. f_equal. simpl in H. lia.
    + rewrite List.rev_length. lia.
  - rewrite !map_app. f_equal.
    rewrite map_subst_instance_constr_to_extended_list_k.
    erewrite to_extended_list_k_map_subst at 2.
    + now rewrite Nat.add_comm.
    + lia.
Qed.

Lemma subst_to_extended_list_k s k args ctx :
  make_context_subst (List.rev ctx) args [] = Some s ->
  map (subst s k) (to_extended_list_k ctx k) = map (lift0 k) args.
Proof.
  move/make_context_subst_spec. rewrite List.rev_involutive.
  move=> H; induction H; simpl; auto.
  - rewrite map_app -IHcontext_subst //.
    rewrite to_extended_list_k_cons /= !map_app.
    f_equal.
    + rewrite (lift_to_extended_list_k _ _ 1) map_map_compose.
      pose proof (to_extended_list_k_spec Γ k).
      solve_all. destruct H0 as [n [-> Hn]].
      rewrite /lift (subst_app_decomp [a] s k); auto with wf.
      rewrite subst_rel_gt.
      * simpl. lia.
      * unf_term. repeat (f_equal; simpl; try lia).
    + now rewrite /map (subst_rel_eq _ _ 0 a).
  - rewrite -IHcontext_subst // to_extended_list_k_cons /=.
    rewrite (lift_to_extended_list_k _ _ 1) map_map_compose.
    pose proof (to_extended_list_k_spec Γ k).
    solve_all. destruct H0 as [n [-> Hn]].
    rewrite /lift (subst_app_decomp [subst0 s b] s k); auto with wf.
    rewrite subst_rel_gt.
    + simpl; lia.
    + unf_term. repeat (f_equal; simpl; try lia).
Qed.


Lemma Alli_map_option_out_mapi_Some_spec' {A B} (f g : nat -> A -> option B) h l t P :
  All P l ->
  (forall i x t, P x -> f i x = Some t -> g i x = Some (h t)) ->
  map_option_out (mapi f l) = Some t ->
  map_option_out (mapi g l) = Some (map h t).
Proof.
  unfold mapi. generalize 0.
  move => n Ha Hfg. move: t.
  induction Ha in n |- *; try constructor; auto.
  - destruct t; cbnr; discriminate.
  - move=> t /=. case E: (f n x) => [b|]; try congruence.
    rewrite (Hfg n _ _ p E).
    case E' : map_option_out => [b'|]; try congruence.
    move=> [= <-]. now rewrite (IHHa _ _ E').
Qed.

Lemma map_subst_instance_constr_to_extended_list_k u ctx k :
  to_extended_list_k (subst_instance_context u ctx) k
  = to_extended_list_k ctx k.
Proof.
  unfold to_extended_list_k.
  cut (map (subst_instance_constr u) [] = []); [|reflexivity].
  unf_term. generalize (nil term); intros l Hl.
  induction ctx in k, l, Hl |- *; cbnr.
  destruct a as [? [] ?]; cbnr; eauto.
  unf_term. eapply IHctx; cbn; congruence.
Qed.

Lemma subst_build_case_predicate_type ind mdecl idecl u params ps pty n k :
  closed_ctx (subst_instance_context u (ind_params mdecl)) ->
  closed (ind_type idecl) ->
  build_case_predicate_type ind mdecl idecl params u ps = Some pty ->
  build_case_predicate_type ind mdecl
    (map_one_inductive_body (context_assumptions mdecl.(ind_params))
            (length (arities_context (ind_bodies mdecl))) (fun k' => subst n (k' + k))
            (inductive_ind ind) idecl)
    (map (subst n k) params) u ps
  = Some (subst n k pty).
Proof.
  intros closedparams closedtype.
  unfold build_case_predicate_type; simpl.
  case_eq (instantiate_params (subst_instance_context u (ind_params mdecl)) params
                              (subst_instance_constr u (ind_type idecl)));
    [|discriminate ].
  intros ipars Hipars.
  apply (subst_instantiate_params n k) in Hipars; tas.
  rewrite ind_type_map. simpl.
  rewrite subst_closedn in Hipars.
  { rewrite closedn_subst_instance_constr; eapply closed_upwards; tea; lia. }
  rewrite subst_closedn; [eapply closed_upwards; tea; lia|].
  rewrite Hipars.
  specialize (subst_destArity [] ipars n k);
    destruct (destArity [] ipars) as [[ctx s]|]; [|discriminate].
  simpl. cbn. move => -> /some_inj-HH. simpl. f_equal.
  etransitivity.
  2: exact (f_equal (subst n k) HH).
  rewrite subst_it_mkProd_or_LetIn. unf_term. simpl. f_equal. f_equal.
  { destruct idecl; reflexivity. }
  rewrite subst_mkApps; simpl. f_equal.
  rewrite map_app; f_equal.
  - rewrite !map_map; apply map_ext; clear; intro.
    rewrite subst_context_length.
    rewrite -> commut_lift_subst_rec by lia.
    f_equal. lia.
  - rewrite /to_extended_list to_extended_list_k_subst.
    rewrite <- to_extended_list_k_map_subst by lia. reflexivity.
Qed.

Lemma subst_build_branches_type {cf:checker_flags}
      n k Σ ind mdecl idecl indices args u p brs cs :
  wf Σ ->
  declared_inductive Σ mdecl ind idecl ->
  closed_ctx (subst_instance_context u (ind_params mdecl)) ->
  on_inductive (lift_typing typing) (Σ, ind_universes mdecl)
               (inductive_mind ind) mdecl ->
  on_constructors (lift_typing typing) (Σ, ind_universes mdecl)
                  mdecl (inductive_ind ind) idecl indices (ind_ctors idecl) cs ->
  map_option_out (build_branches_type ind mdecl idecl args u p) = Some brs ->
  map_option_out (build_branches_type ind mdecl
         idecl (map (subst n k) args) u (subst n k p)) =
         Some (map (on_snd (subst n k)) brs).
Proof.
  intros wfΣ wfidecl closedparams onmind Honcs.
  rewrite !build_branches_type_. cbn.
  eapply Alli_map_option_out_mapi_Some_spec'.
  { eapply All2_All_left; tea. intros x y u'; exact (y; u'). }
  clear Honcs brs.
  intros j [[id t] i] [t' k'] [cs' Honc].
  case_eq (instantiate_params (subst_instance_context u (ind_params mdecl)) args
                              (subst0 (inds (inductive_mind ind) u
                                            (ind_bodies mdecl))
                                      (subst_instance_constr u t)));
    [|discriminate].
  intros ty Heq; cbn.
  pose proof (on_constructor_closed wfΣ (u:=u) Honc) as clt; cbn in clt.
  eapply (closed_upwards k) in clt; try lia.
  remember (subst0 (inds (inductive_mind ind) u (ind_bodies mdecl))
                   (subst_instance_constr u t)) as ty'.
  apply (subst_instantiate_params n k) in Heq as Heq'; tas.
  erewrite subst_closedn in Heq'; tas.
  rewrite Heq'.
  eapply instantiate_params_make_context_subst in Heq.
  destruct Heq as [ctx' [ty'' [s' [Hty [Hsubst Ht0]]]]].
  subst ty; simpl.
  rewrite Heqty' in Hty.
  destruct Honc as [Hcshape_args ? cshape_eq Hty' _ _]; unfold cdecl_type in *; simpl in *.
  rewrite cshape_eq in Hty.
  rewrite -> !subst_instance_constr_it_mkProd_or_LetIn in Hty.
  rewrite !subst_it_mkProd_or_LetIn in Hty.
  assert (H0: #|subst_context (inds (inductive_mind ind) u (ind_bodies mdecl)) 0
                (subst_instance_context u (ind_params mdecl))|
          = #|subst_instance_context u (ind_params mdecl)|). {
    now rewrite subst_context_length. }
  rewrite <- H0 in Hty.
  rewrite decompose_prod_n_assum_it_mkProd in Hty.
  injection Hty. clear Hty.
  intros Heqty'' <-. revert Heqty''.
  rewrite !subst_instance_context_length Nat.add_0_r.
  rewrite subst_context_length subst_instance_context_length.
  rewrite (subst_cstr_concl_head ind u mdecl cs'.(cshape_args) cs'.(cshape_indices)).
  { destruct wfidecl as [Hmdecl Hnth].
    now apply nth_error_Some_length in Hnth.
  }
  intros <-. rewrite !subst_it_mkProd_or_LetIn !subst_mkApps /=.
  rewrite !decompose_prod_assum_it_mkProd /=;
          try by rewrite is_ind_app_head_mkApps.
  rewrite !decompose_app_mkApps; try by reflexivity.
  simpl. rewrite !map_app !subst_context_length
                 !subst_instance_context_length Nat.add_0_r.
  eapply subst_to_extended_list_k with (k:=#|cs'.(cshape_args)|) in Hsubst as XX.
  rewrite map_subst_instance_constr_to_extended_list_k in XX.
  rewrite !XX; clear XX.
  apply make_context_subst_spec in Hsubst as Hsubst'.
  rewrite rev_involutive in Hsubst'.
  pose proof (context_subst_assumptions_length _ _ _ Hsubst') as H1.
  case E: chop => [l l'].
  have chopm := (chop_map _ _ _ _ _ E).
  move: E chopm.
  rewrite chop_n_app ?map_length. {
    rewrite <- H1. apply onNpars in onmind.
    now rewrite subst_instance_context_assumptions. }
  move=> [= <- <-] chopm.
  move: {chopm}(chopm _ (subst n (#|cs'.(cshape_args)| + k))).
  rewrite map_app.
  move=> chopm; rewrite {}chopm /=.
  inversion 1; subst. f_equal. unfold on_snd; cbn; f_equal.
  rewrite !app_nil_r /on_snd /=.
  rewrite subst_it_mkProd_or_LetIn !subst_context_length !subst_mkApps
          !subst_instance_context_length !map_app.
  f_equal. f_equal.
  -- rewrite -> commut_lift_subst_rec by lia. arith_congr.
  -- f_equal. simpl. f_equal.
     rewrite !subst_mkApps /= !map_app. f_equal.
     f_equal.
     rewrite /to_extended_list -to_extended_list_k_map_subst.
     ++ rewrite !subst_context_length subst_instance_context_length. lia.
     ++ now rewrite to_extended_list_k_subst.
Qed.


Hint Unfold subst1 : subst.
Hint Rewrite subst_mkApps distr_subst: subst.

Inductive untyped_subslet (Γ : context) : list term -> context -> Type :=
| untyped_emptyslet : untyped_subslet Γ [] []
| untyped_cons_let_ass Δ s na t T :
    untyped_subslet Γ s Δ ->
    untyped_subslet Γ (t :: s) (Δ ,, vass na T)
| untyped_cons_let_def Δ s na t T :
    untyped_subslet Γ s Δ ->
    untyped_subslet Γ (subst0 s t :: s) (Δ ,, vdef na t T).
 
Lemma decompose_prod_assum_it_mkProd_or_LetIn ctx t ctx' t' :
 decompose_prod_assum ctx t = (ctx', t') -> 
 it_mkProd_or_LetIn ctx t = it_mkProd_or_LetIn ctx' t'.
Proof.
  induction t in ctx, ctx', t' |- *; simpl; try intros [= -> <-]; auto.
  - intros H. now apply IHt2 in H.
  - intros H. now apply IHt3 in H.
Qed.

Inductive decompose_prod_assum_graph : term -> (context * term) -> Type :=
| decompose_arity ctx t : decompose_prod_assum_graph (it_mkProd_or_LetIn ctx t) (ctx, t).

Lemma decompose_prod_assum_spec ctx t : 
  decompose_prod_assum_graph (it_mkProd_or_LetIn ctx t) (decompose_prod_assum ctx t).
Proof.
 induction t in ctx |- *; simpl; try constructor 1.
 - specialize (IHt2 (vass na t1 :: ctx)).
   apply IHt2.
 - apply (IHt3 (vdef na t1 t2 :: ctx)).
Qed.

Lemma subst_decompose_prod_assum_rec ctx t s k :
  let (ctx', t') := decompose_prod_assum ctx t in
  ∑ ctx'' t'', 
    (decompose_prod_assum [] (subst s (#|ctx'| + k) t') = (ctx'', t'')) *
  (decompose_prod_assum (subst_context s k ctx) (subst s (length ctx + k) t) =
  (subst_context s k ctx' ,,, ctx'', t'')).
Proof.
  induction t in ctx, k |- *; simpl; try solve [ eexists _, _; firstorder eauto ].
  - elim: leb_spec_Set => comp.
    + destruct (nth_error s (n - (#|ctx| + k))) eqn:Heq.
      * destruct decompose_prod_assum eqn:Heq'.
        eexists _, _; intuition eauto.
        now rewrite decompose_prod_assum_ctx Heq'.
      * eexists _,_; firstorder eauto.
    + eexists _,_; firstorder eauto.
  - destruct decompose_prod_assum eqn:Heq.
    rewrite decompose_prod_assum_ctx in Heq.
    destruct (decompose_prod_assum [] t2) eqn:Heq'.
    noconf Heq.
    specialize (IHt2 ctx (S k)).
    rewrite decompose_prod_assum_ctx in IHt2.
    rewrite Heq' in IHt2.
    destruct IHt2 as [ctx'' [t'' [eqt eqt2]]].
    exists ctx'', t''. rewrite -eqt.
    split.
    * unfold snoc; simpl. rewrite !app_context_length.
      simpl. lia_f_equal.
    * rewrite decompose_prod_assum_ctx in eqt2.
      rewrite decompose_prod_assum_ctx.
      rewrite Nat.add_succ_r in eqt2.
      destruct (decompose_prod_assum   []  (subst s _ t2)) eqn:Heq''.
      rewrite subst_context_app in eqt2.
      rewrite !subst_context_app subst_context_snoc.
      injection eqt2. intros <-.
      intros eqctx. f_equal.
      unfold app_context in eqctx.
      rewrite app_assoc in eqctx.
      apply app_inv_tail in eqctx.
      subst c. rewrite app_context_assoc.
      unfold snoc. simpl. lia_f_equal.
  - destruct decompose_prod_assum eqn:Heq.
    rewrite decompose_prod_assum_ctx in Heq.
    destruct (decompose_prod_assum [] t3) eqn:Heq'.
    noconf Heq.
    specialize (IHt3 ctx (S k)).
    rewrite decompose_prod_assum_ctx in IHt3.
    rewrite Heq' in IHt3.
    destruct IHt3 as [ctx'' [t'' [eqt eqt3]]].
    exists ctx'', t''. rewrite -eqt.
    split.
    * unfold snoc; simpl. rewrite !app_context_length.
      simpl. lia_f_equal.
    * rewrite decompose_prod_assum_ctx in eqt3.
      rewrite decompose_prod_assum_ctx.
      rewrite Nat.add_succ_r in eqt3.
      destruct (decompose_prod_assum   []  (subst s _ t3)) eqn:Heq''.
      rewrite subst_context_app in eqt3.
      rewrite !subst_context_app subst_context_snoc.
      injection eqt3. intros <-.
      intros eqctx. f_equal.
      unfold app_context in eqctx.
      rewrite app_assoc in eqctx.
      apply app_inv_tail in eqctx.
      subst c. rewrite app_context_assoc.
      unfold snoc. simpl. lia_f_equal.
Qed.
(* 

Lemma subst_decompose_prod_assum_rec ctx t s k :
  let (ctx', t') := decompose_prod_assum ctx t in
  let (ctx'', t'') := decompose_prod_assum (subst_context s k ctx) (subst s (length ctx + k) t) in 
  subst s k (it_mkProd_or_LetIn ctx' t') = it_mkProd_or_LetIn ctx'' t''.
Proof.
  rewrite decompose_prod_assum_ctx.
  destruct decompose_prod_assum eqn:Heq.
  destruct (decompose_prod_assum (subst_context _ _ _) _) eqn:Heq'.
  apply decompose_prod_assum_it_mkProd_or_LetIn in Heq.
  apply decompose_prod_assum_it_mkProd_or_LetIn in Heq'.
  rewrite subst_it_mkProd_or_LetIn.
  rewrite subst_context_app.
  rewrite it_mkProd_or_LetIn_app.
  rewrite -Heq'. f_equal.
  simpl in Heq.
  rewrite Heq.
  rewrite subst_it_mkProd_or_LetIn.
  rewrite app_context_length.
  lia_f_equal.
Qed. *)

Lemma smash_context_subst Δ s n Γ : smash_context (subst_context s (n + #|Γ|) Δ) (subst_context s n Γ) =
  subst_context s n (smash_context Δ Γ).
Proof.
  revert Δ. induction Γ as [|[na [b|] ty]]; intros Δ; simpl; auto.
  - now rewrite Nat.add_0_r.
  - rewrite -IHΓ.
    rewrite subst_context_snoc /=. f_equal.
    rewrite !subst_context_alt !mapi_compose.
    apply mapi_ext=> n' x.
    destruct x as [na' [b'|] ty']; simpl.
    * rewrite !mapi_length /subst_decl /= /map_decl /=; f_equal.
      + rewrite Nat.add_0_r distr_subst_rec. simpl. lia_f_equal. 
      + rewrite Nat.add_0_r distr_subst_rec; simpl. lia_f_equal.
    * rewrite !mapi_length /subst_decl /= /map_decl /=; f_equal.
      rewrite Nat.add_0_r distr_subst_rec /=. lia_f_equal.
  - rewrite -IHΓ.
    rewrite subst_context_snoc /= // /subst_decl /map_decl /=.
    f_equal.
    rewrite subst_context_app. simpl.
    rewrite /app_context. f_equal.
    + lia_f_equal.
    + rewrite /subst_context // /fold_context /= /map_decl /=.
      lia_f_equal.
Qed.

Lemma smash_context_app Δ Γ Γ' : smash_context Δ (Γ ++ Γ')%list = smash_context (smash_context Δ Γ) Γ'.
Proof.
  revert Δ; induction Γ as [|[na [b|] ty]]; intros Δ; simpl; auto.
Qed.


(* Smashing a context Γ with Δ depending on it is the same as smashing Γ
     and substituting all references to Γ in Δ by the expansions of let bindings.
  *)

Arguments Nat.sub : simpl nomatch.

Fixpoint extended_subst (Γ : context) (n : nat) 
  (* Δ, smash_context Γ, n |- extended_subst Γ n : Γ *) :=
  match Γ with
  | nil => nil
  | cons d vs =>
    match decl_body d with
    | Some b =>
      (* Δ , vs |- b *)
      let s := extended_subst vs n in
      (* Δ , smash_context vs , n |- s : vs *)
      let b' := lift (context_assumptions vs + n) #|s| b in
      (* Δ, smash_context vs, n , vs |- b' *)
      let b' := subst0 s b' in
      (* Δ, smash_context vs , n |- b' *)
      b' :: s
    | None => tRel n :: extended_subst vs (S n)
    end
  end.

Lemma extended_subst_length Γ n : #|extended_subst Γ n| = #|Γ|.
Proof.
  induction Γ in n |- *; simpl; auto.
  now destruct a as [? [?|] ?] => /=; simpl; rewrite IHΓ. 
Qed.
Hint Rewrite extended_subst_length : len.

Lemma assumption_context_skipn Γ n : 
  assumption_context Γ -> 
  assumption_context (skipn n Γ).
Proof.
  induction 1 in n |- *; simpl.
  - destruct n; constructor.
  - destruct n. 
    * rewrite skipn_0. constructor; auto.
    * now rewrite skipn_S.
Qed.

Hint Rewrite idsn_length : len.

Lemma subst_fn_eq s s' x : s = s' -> subst_fn s x = subst_fn s' x.
Proof.
  intros -> ; reflexivity.
Qed.

Lemma lift_extended_subst (Γ : context) k : 
  extended_subst Γ k = map (lift0 k) (extended_subst Γ 0).
Proof.
  induction Γ as [|[? [] ?] ?] in k |- *; simpl; auto.
  - rewrite IHΓ. f_equal.
    autorewrite with len.
    rewrite distr_lift_subst. f_equal.
    autorewrite with len. rewrite simpl_lift; lia_f_equal.
  - rewrite Nat.add_0_r; f_equal.
    rewrite IHΓ (IHΓ 1).
    rewrite map_map_compose. apply map_ext => x.
    rewrite simpl_lift; try lia.
    now rewrite Nat.add_1_r.
Qed.

Lemma extended_subst_subst_instance_constr u Γ n :
  map (subst_instance_constr u) (extended_subst Γ n) =
  extended_subst (subst_instance_context u Γ) n.
Proof.
  induction Γ as [|[?[]?] ?] in n |- *; simpl; auto.
  - autorewrite with len.
    f_equal; auto.
    rewrite -subst_subst_instance_constr.
    rewrite -lift_subst_instance_constr.
    rewrite subst_instance_context_assumptions.
    f_equal. apply IHΓ.
  - f_equal; auto.
Qed.

Local Open Scope sigma_scope.

Lemma inst_extended_subst_shift (Γ : context) k : 
  map (inst ((extended_subst Γ 0 ⋅n ids) ∘s ↑^k)) (idsn #|Γ|) =
  map (inst (extended_subst Γ k ⋅n ids)) (idsn #|Γ|).
Proof.
  intros.
  rewrite !map_idsn_spec.
  apply nat_recursion_ext => x l' Hx.
  f_equal. f_equal.
  edestruct (@subst_consn_lt _ (extended_subst Γ k) x) as [d [Hd Hσ]].
  { now (autorewrite with len; lia). }
  simpl. rewrite Hσ.
  edestruct (@subst_consn_lt _ (extended_subst Γ 0) x) as [d' [Hd' Hσ']];
    try (autorewrite with len; trivial).
  unfold subst_compose. rewrite Hσ'.
  apply some_inj.
  rewrite -Hd. change (Some d'.[↑^k]) with (option_map (fun x => inst (↑^k) x) (Some d')).
  rewrite -Hd'.
  rewrite (lift_extended_subst _ k).
  rewrite nth_error_map. apply option_map_ext => t.
  now autorewrite with sigma.
Qed.

Lemma subst_context_decompo s s' Γ k : 
  subst_context (s ++ s') k Γ =
  subst_context s' k (subst_context (map (lift0 #|s'|) s) k Γ).
Proof.
  intros.
  rewrite !subst_context_alt !mapi_compose.
  apply mapi_ext => i x.
  destruct x as [na [b|] ty] => //.
  - rewrite /subst_decl /map_decl /=; f_equal.
    + rewrite !mapi_length. f_equal.
      now rewrite subst_app_decomp.
    + rewrite mapi_length.
      now rewrite subst_app_decomp.
  - rewrite /subst_decl /map_decl /=; f_equal.
    rewrite !mapi_length. now rewrite subst_app_decomp.
Qed.

Lemma fold_context_compose f g Γ : 
  fold_context f (fold_context g Γ) = fold_context (fun n x => f n (g n x)) Γ.
Proof.
  induction Γ; simpl; auto; rewrite !fold_context_snoc0.
  simpl. rewrite IHΓ. f_equal.
  rewrite PCUICAstUtils.compose_map_decl.
  now rewrite fold_context_length.
Qed.

Lemma fold_context_ext f g Γ : 
  f =2 g ->
  fold_context f Γ = fold_context g Γ.
Proof.
  intros hfg.
  induction Γ; simpl; auto; rewrite !fold_context_snoc0.
  simpl. rewrite IHΓ. f_equal. apply PCUICAstUtils.map_decl_ext.
  intros. now apply hfg.
Qed.

Lemma smash_context_acc Γ Δ : 
  smash_context Δ Γ =
      subst_context (extended_subst Γ 0) 0 (lift_context (context_assumptions Γ) #|Γ| Δ)
   ++ smash_context [] Γ.
Proof.
  revert Δ.
  induction Γ as [|[? [] ?] ?]; intros Δ.
  - simpl; auto.
    now rewrite subst0_context app_nil_r lift0_context.
  - simpl. autorewrite with len.
    rewrite IHΓ; auto.
    rewrite subst_context_nil. f_equal.
    rewrite (subst_context_decompo [_] _).
    simpl. autorewrite with len.
    rewrite lift0_id.
    rewrite subst0_context.
    unfold subst_context, lift_context.
    rewrite !fold_context_compose.
    apply fold_context_ext. intros n n' -> x.
    rewrite Nat.add_0_r.
    autorewrite with sigma.
    apply inst_ext.
    setoid_rewrite ren_lift_renaming.
    autorewrite with sigma.
    rewrite !Upn_compose.
    apply Upn_ext. 
    autorewrite with sigma.
    unfold Up.
    rewrite subst_consn_subst_cons.
    autorewrite with sigma.
    reflexivity.
    
  - simpl.
    rewrite IHΓ /=. auto.
    rewrite (IHΓ [_]). auto. rewrite !app_assoc. f_equal.
    rewrite app_nil_r. unfold map_decl. simpl. unfold app_context.
    simpl. rewrite lift_context_app subst_context_app /app_context. simpl.
    unfold lift_context at 2. unfold subst_context at 2, fold_context. simpl.
    f_equal.
    unfold subst_context, lift_context.
    rewrite !fold_context_compose.
    apply fold_context_ext. intros n n' ->. intros x.
    rewrite Nat.add_0_r.

    autorewrite with sigma.
    apply inst_ext. rewrite !ren_lift_renaming.
    autorewrite with sigma.
    rewrite !Upn_compose.
    autorewrite with sigma.
    apply Upn_ext.
    unfold Up.
    
    rewrite subst_consn_subst_cons.
    autorewrite with sigma.
    apply subst_cons_proper; auto.
    rewrite !Upn_eq. autorewrite with sigma.
    rewrite subst_consn_compose.
    setoid_rewrite subst_consn_compose at 2 3.
    apply subst_consn_proper.
    { rewrite -inst_extended_subst_shift; auto. }

    autorewrite with sigma.
    rewrite -subst_compose_assoc.
    rewrite shiftk_compose.
    autorewrite with sigma.
    setoid_rewrite <- (compose_ids_l ↑) at 2.
    rewrite -subst_consn_compose.
    rewrite - !subst_compose_assoc.
    rewrite -shiftk_shift shiftk_compose.
    autorewrite with sigma.
    rewrite subst_consn_compose.
    rewrite -shiftk_compose subst_compose_assoc.
    rewrite subst_consn_shiftn.
    2:now autorewrite with len.
    autorewrite with sigma. 
    rewrite -shiftk_shift.
    rewrite -shiftk_compose subst_compose_assoc.
    rewrite subst_consn_shiftn.
    2:now autorewrite with len.
    now autorewrite with sigma.
Qed.

Hint Rewrite context_assumptions_app context_assumptions_fold : len.

Lemma map_option_out_impl {A B} (l : list A) (f g : A -> option B) x : 
  (forall x y, f x = Some y -> g x = Some y) ->
  map_option_out (map f l) = Some x ->
  map_option_out (map g l) = Some x.
Proof.
  intros Hfg.
  induction l in x |- *; simpl; auto.
  destruct (f a) eqn:fa.
  - rewrite (Hfg _ _ fa).
    move: IHl; destruct map_option_out.
    * move=> H'. specialize (H' _ eq_refl).
      rewrite H'. congruence.
    * discriminate.
  - discriminate.
Qed.

Lemma substitution_check_one_fix s k mfix inds :
  map_option_out (map check_one_fix mfix) = Some inds ->
  map_option_out (map (fun x : def term =>
    check_one_fix (map_def (subst s k) (subst s (#|mfix| + k)) x)) mfix) = Some inds.
Proof.
  apply map_option_out_impl.
  move=> [na ty def rarg] /=.
  rewrite decompose_prod_assum_ctx.
  destruct (decompose_prod_assum _ ty) eqn:decomp.
  rewrite decompose_prod_assum_ctx in decomp.
  destruct (decompose_prod_assum [] ty) eqn:decty.
  noconf decomp. rewrite !app_context_nil_l.
  pose proof (subst_decompose_prod_assum_rec [] ty s k).
  rewrite decty in X.
  destruct X as [ctx'' [t'' [dect decty']]].
  rewrite subst_context_nil in decty'; simpl in decty'.
  rewrite decty'. intros ind.
  rewrite smash_context_app.
  rewrite (smash_context_acc _ (smash_context _ _)).
  rewrite List.rev_app_distr.
  destruct (nth_error_spec (List.rev (smash_context [] c0)) rarg) => /= //;
  autorewrite with len in l; simpl in *.
  rewrite nth_error_app_lt; autorewrite with len; simpl; try lia. 
  rewrite (smash_context_subst []) /=.
  rewrite nth_error_rev_inv; autorewrite with len; simpl; try lia.
  rewrite nth_error_subst_context /=.
  autorewrite with len.
  rewrite nth_error_rev_inv in e; autorewrite with len; auto.
  autorewrite with len in e. simpl in e. rewrite e.
  simpl.
  destruct (decompose_app (decl_type x)) eqn:Happ.
  destruct t0; try discriminate. simpl in *.
  erewrite decompose_app_subst; eauto. simpl. auto.
Qed.
 
Lemma decompose_prod_assum_mkApps ctx ind u args :
  decompose_prod_assum ctx (mkApps (tInd ind u) args) = (ctx, mkApps (tInd ind u) args).
Proof.
  apply (decompose_prod_assum_it_mkProd ctx []).
  now rewrite is_ind_app_head_mkApps.
Qed.

Lemma substitution_check_one_cofix s k mfix inds :
  map_option_out (map check_one_cofix mfix) = Some inds ->
  map_option_out (map (fun x : def term =>
     check_one_cofix (map_def (subst s k) (subst s (#|mfix| + k)) x)) mfix) = Some inds.
Proof.
  apply map_option_out_impl. move=> [na ty def rarg] /= ind.
  destruct (decompose_prod_assum [] ty) eqn:decty.
  destruct (decompose_app t) eqn:eqapp.
  destruct t0; try discriminate. simpl.
  pose proof (subst_decompose_prod_assum_rec [] ty s k).
  rewrite decty in X.
  destruct X as [ctx'' [t'' [dect decty']]].
  rewrite decty'.
  apply decompose_app_inv in eqapp.
  subst t.
  rewrite subst_mkApps /= in dect.
  rewrite decompose_prod_assum_mkApps in dect. noconf dect.
  rewrite decompose_app_mkApps //.
Qed.

Lemma subs_nth_error {cf:checker_flags} Σ Γ s Δ decl n t :
  subs Σ Γ s Δ ->
  nth_error Δ n = Some decl ->
  nth_error s n = Some t ->
  match decl_body decl return Type with
  | Some t' => False
  | None =>
    let ty := subst0 (skipn (S n) s) (decl_type decl) in
    Σ ;;; Γ |- t : ty
  end.
Proof.
  induction 1 in n |- *; simpl; auto; destruct n; simpl; try congruence.
  - intros [= <-]. intros [= ->].
    simpl. exact t1.
  - intros. destruct decl as [na' [b|] ty]; cbn in *.
    + eapply IHX. all: eauto.
    + now apply IHX.
Qed.

Lemma untyped_subslet_nth_error Γ s Δ decl n t :
  untyped_subslet Γ s Δ ->
  nth_error Δ n = Some decl ->
  nth_error s n = Some t ->
  match decl_body decl return Type with
  | Some t' => t = subst0 (skipn (S n) s) t'
  | None => True
  end.
Proof.
  induction 1 in n |- *; simpl; auto; destruct n; simpl; try congruence.
  - intros [= <-]. intros [= ->].
    simpl. auto.
  - intros. destruct decl as [na' [b|] ty]; cbn in *. 2: auto.
    specialize (IHX _ H H0). intuition auto.
  - intros [= <-]. intros [= <-].
    simpl. split; auto.
  - apply IHX.
Qed.

(* Lemma red1_mkApp Σ Γ M1 N1 M2 : *)
(*   red1 Σ Γ M1 N1 -> red1 Σ Γ (mkApp M1 M2) (mkApp N1 M2). *)
(* Proof. *)
(*   intros wfM1 H. *)
(*   destruct (isApp M1) eqn:Heq. *)
(*   destruct M1; try discriminate. simpl. *)
(*   revert wfM1. inv H. simpl. intros. *)
(*   rewrite mkApp_mkApps. constructor. *)

(*   intros. inv wfM1. simpl. *)
(*   econstructor; eauto. *)
(*   clear -H1. *)
(*   unfold is_constructor in *. *)
(*   destruct (nth_error l narg) eqn:Heq. *)
(*   eapply nth_error_app_left in Heq. now rewrite -> Heq. discriminate. *)

(*   intros. rewrite mkApp_mkApps. now constructor. *)

(*   intros. simpl. *)
(*   constructor. clear -H0. induction H0; constructor; auto. *)

(*   rewrite mkApp_tApp; auto. *)
(*   now apply red1_tApp_mkApp. *)
(* Qed. *)

Lemma red1_mkApps_l Σ Γ M1 N1 M2 :
  red1 Σ Γ M1 N1 -> red1 Σ Γ (mkApps M1 M2) (mkApps N1 M2).
Proof.
  induction M2 in M1, N1 |- *.
  - simpl; auto.
  - intros. specialize (IHM2 (tApp M1 a) (tApp N1 a)).
    forward IHM2.
    { constructor. auto. }
    simpl. auto.
Qed.

Lemma red1_mkApps_r Σ Γ M1 M2 N2 :
  OnOne2 (red1 Σ Γ) M2 N2 -> red1 Σ Γ (mkApps M1 M2) (mkApps M1 N2).
Proof.
  intros. induction X in M1 |- *.
  - simpl. eapply red1_mkApps_l. constructor; auto.
  - apply (IHX (tApp M1 hd)).
Qed.

Arguments iota_red : simpl never.

Lemma substitution_red1 {cf:checker_flags} (Σ : global_env_ext) Γ Γ' Γ'' s M N :
  wf Σ -> subs Σ Γ s Γ' -> wf_local Σ Γ ->
  red1 Σ (Γ ,,, Γ' ,,, Γ'') M N ->
  red1 Σ (Γ ,,, subst_context s 0 Γ'') (subst s #|Γ''| M) (subst s #|Γ''| N).
Proof.
  intros wfΣ Hs wfΓ H.
  remember (Γ ,,, Γ' ,,, Γ'') as Γ0. revert Γ Γ' Γ'' HeqΓ0 wfΓ Hs.
  induction H using red1_ind_all in |- *; intros Γ0 Γ' Γ'' HeqΓ0 wfΓ Hs; try subst Γ; cbn -[iota_red];
  match goal with
    |- context [iota_red _ _ _ _] => idtac
  | |- _ => autorewrite with subst
  end;
    try solve [  econstructor; try inv wfM; eauto ].

  - pose proof (subst_length _ _ _ _ Hs).
    elim (leb_spec_Set); intros Hn.
    + destruct (nth_error s) eqn:Heq.
      * pose proof (nth_error_Some_length Heq).
        rewrite -> nth_error_app_context_ge in H by lia.
        rewrite -> nth_error_app_context_lt in H by lia.
        destruct nth_error eqn:HΓ'.
        -- destruct c as [na [b|] ty]; noconf H.
           eapply subs_nth_error in Heq; eauto. simpl in Heq. destruct Heq.
        -- noconf H.
      * apply nth_error_None in Heq.
        assert(S i = #|s| + (S (i - #|s|))) by lia.
        rewrite H1. rewrite -> simpl_subst; try lia.
        econstructor.
        rewrite nth_error_app_context_ge // in H.
        rewrite nth_error_app_context_ge // in H. 1: lia.
        rewrite -> nth_error_app_context_ge. 2:(autorewrite with wf; lia).
        rewrite <- H. f_equal. f_equal. autorewrite with wf. lia.
    + rewrite -> nth_error_app_context_lt in H by lia.
      pose (commut_lift_subst_rec body s (S i) (#|Γ''| - S i) 0).
      assert(eq:#|Γ''| - S i + S i = #|Γ''|) by lia.
      rewrite -> eq in e. rewrite <- e by lia.
      constructor.
      rewrite -> nth_error_app_context_lt by (autorewrite with wf; lia).
      rewrite -> nth_error_subst_context.
      unfold subst_decl; now rewrite -> option_map_decl_body_map_decl, H, Nat.add_0_r.

  - rewrite subst_iota_red.
    autorewrite with subst.
    constructor.

  - pose proof (subst_declared_constant _ _ _ s #|Γ''| u wfΣ H).
    apply (f_equal cst_body) in H1.
    rewrite <- !map_cst_body in H1. rewrite H0 in H1. simpl in H1.
    injection H1. intros ->.
    econstructor. all: eauto.

  - simpl. constructor.
    now rewrite nth_error_map H.

  - constructor.
    specialize (IHred1 Γ0 Γ' (Γ'' ,, vass na N) eq_refl).
    now rewrite subst_context_snoc0 in IHred1.

  - constructor.
    specialize (IHred1 Γ0 Γ' (Γ'' ,, _) eq_refl).
    now rewrite subst_context_snoc0 in IHred1.

  - constructor.
    induction X; constructor; auto.
    intuition; eauto.

  - constructor. specialize (IHred1 _ _ (Γ'' ,, vass na M1) eq_refl).
    now rewrite subst_context_snoc0 in IHred1.

  - constructor.
    induction X; constructor; auto.
    intuition.

  - constructor.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    induction X; simpl; constructor; simpl; intuition auto.
    + eapply b0; eauto.
    + congruence.

  - apply fix_red_body. rewrite !subst_fix_context.
    solve_all.
    rewrite <- (OnOne2_length X).
    eapply OnOne2_map. unfold on_Trel; solve_all.
    + rename_all_hyps.
      specialize (forall_Γ Γ0 Γ' (Γ'' ,,, fix_context mfix0)).
      rewrite app_context_assoc in forall_Γ. specialize (forall_Γ eq_refl).
      rewrite -> app_context_length, fix_context_length in *.
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      auto.
    + cbn; congruence.

  - constructor.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    !induction X; simpl; constructor; auto.
    intuition auto.
    + rename_all_hyps. eapply forall_Γ; eauto.
    + simpl. congruence.

  - apply cofix_red_body. rewrite !subst_fix_context.
    solve_all.
    rewrite <- (OnOne2_length X).
    eapply OnOne2_map. unfold on_Trel; solve_all.
    + rename_all_hyps.
      specialize (forall_Γ Γ0 Γ' (Γ'' ,,, fix_context mfix0)).
      rewrite app_context_assoc in forall_Γ. specialize (forall_Γ eq_refl).
      rewrite -> app_context_length, fix_context_length in *.
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      auto.
    + cbn; congruence.
Qed.

Lemma subst_skipn n s k t : n <= #|s| -> subst (skipn n s) k t = subst s k (lift n k t).
Proof.
  intros Hn.
  assert (#|firstn n s| = n) by (rewrite firstn_length_le; lia).
  rewrite <- (firstn_skipn n s) at 2.
  rewrite subst_app_simpl. rewrite H.
  rewrite <- commut_lift_subst_rec; auto with arith.
  rewrite -{3}H. now rewrite simpl_subst_k.
Qed.

Lemma substitution_let_red `{cf : checker_flags} (Σ : global_env_ext) Γ Δ Γ' s M N :
  wf Σ -> subslet Σ Γ s Δ -> wf_local Σ Γ ->
  red1 Σ (Γ ,,, Δ ,,, Γ') M N ->
  red Σ (Γ ,,, subst_context s 0 Γ') (subst s #|Γ'| M) (subst s #|Γ'| N).
Proof.
  intros wfΣ Hs wfΓ H.
  remember (Γ ,,, Δ ,,, Γ') as Γ0. revert Γ Δ Γ' HeqΓ0 wfΓ Hs.
  induction H using red1_ind_all in |- *; intros Γ0 Δ Γ' HeqΓ0 wfΓ Hs; try subst Γ; cbn -[iota_red];
  match goal with
    |- context [iota_red _ _ _ _] => idtac
  | |- _ => autorewrite with subst
  end;
    try solve [ apply red1_red; econstructor; try inv wfM; eauto ].

  - pose proof (subslet_length Hs).
    elim (leb_spec_Set); intros Hn.
    + destruct (nth_error s) eqn:Heq.
      * pose proof (nth_error_Some_length Heq).
        rewrite -> nth_error_app_context_ge in H by lia.
        rewrite -> nth_error_app_context_lt in H by lia.
        destruct nth_error eqn:HΓ'.
        -- destruct c as [na [b|] ty]; noconf H.
           eapply subslet_nth_error in Heq; eauto. simpl in Heq. destruct Heq.
           subst t.
           pose (commut_lift_subst_rec body (skipn (S (i - #|Γ'|)) s) #|Γ'| 0 0).
           forward e by lia. rewrite e.
           simpl. rewrite subst_skipn. 1: auto with arith.
           rewrite simpl_lift; auto with arith.
           assert(S (i - #|Γ'|) + #|Γ'| = S i) as -> by lia.
           constructor.
        -- noconf H.
      * apply nth_error_None in Heq.
        assert(S i = #|s| + (S (i - #|s|))) by lia.
        rewrite H1. rewrite -> simpl_subst; try lia.
        apply red1_red.
        econstructor.
        rewrite nth_error_app_context_ge // in H.
        rewrite nth_error_app_context_ge // in H. 1: lia.
        rewrite -> nth_error_app_context_ge. 2:(autorewrite with wf; lia).
        rewrite <- H. f_equal. f_equal. autorewrite with wf. lia.
    + rewrite -> nth_error_app_context_lt in H by lia.
      pose (commut_lift_subst_rec body s (S i) (#|Γ'| - S i) 0).
      assert(eq:#|Γ'| - S i + S i = #|Γ'|) by lia.
      rewrite -> eq in e. rewrite <- e by lia.
      apply red1_red. constructor.
      rewrite -> nth_error_app_context_lt by (autorewrite with wf; lia).
      rewrite -> nth_error_subst_context.
      unfold subst_decl; now rewrite -> option_map_decl_body_map_decl, H, Nat.add_0_r.

  - rewrite subst_iota_red.
    autorewrite with subst.
    apply red1_red; constructor.

  - pose proof (subst_declared_constant _ _ _ s #|Γ'| u wfΣ H).
    apply (f_equal cst_body) in H1.
    rewrite <- !map_cst_body in H1. rewrite H0 in H1. simpl in H1.
    injection H1. intros ->. apply red1_red.
    econstructor. all: eauto.

  - simpl. apply red1_red; constructor.
    now rewrite nth_error_map H.

  - specialize (IHred1 Γ0 Δ Γ' eq_refl wfΓ Hs).
    apply red_abs. 1: auto. constructor.

  - specialize (IHred1 Γ0 Δ (Γ' ,, _) eq_refl wfΓ Hs).
    apply red_abs; auto.
    now rewrite subst_context_snoc0 in IHred1.

  - specialize (IHred1 _ _ Γ' eq_refl wfΓ Hs).
    apply red_letin; auto.

  - specialize (IHred1 _ _ Γ' eq_refl wfΓ Hs).
    apply red_letin; auto.

  - specialize (IHred1 _ _ (Γ' ,, _) eq_refl wfΓ Hs).
    apply red_letin; auto.
    now rewrite subst_context_snoc0 in IHred1.

  - simplify_IH_hyps. eapply red_case; auto.
    apply All2_map, All2_same. intros. split; auto.

  - simplify_IH_hyps. eapply red_case; auto.
    apply All2_map, All2_same. intros. split; auto.

  - simplify_IH_hyps. apply red_case; auto.
    apply All2_map.
    eapply OnOne2_All2; eauto. simpl. intuition eauto.

  - apply red_proj_c. eauto.

  - apply red_app; eauto.

  - eapply red_app; eauto.

  - eapply red_prod; eauto.

  - eapply red_prod; eauto.
    specialize (IHred1 _ _ (_ ,, _) eq_refl wfΓ Hs).
    simpl in IHred1. now rewrite subst_context_snoc0 in IHred1.

  - eapply red_evar; eauto.
    eapply All2_map. eapply OnOne2_All2; tea; cbnr.
    intuition.

  - eapply red_fix_one_ty.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    intros.
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_fix_one_body.
    rewrite -> (OnOne2_length X).
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + cbn. specialize (ih Γ0 Δ (Γ' ,,, fix_context mfix0)).
      rewrite app_context_assoc in ih.
      specialize (ih eq_refl wfΓ Hs).
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      rewrite app_context_length in ih.
      rewrite fix_context_length in ih.
      rewrite <- subst_fix_context in ih.
      rewrite <- (OnOne2_length X).
      eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_cofix_one_ty.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    intros.
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_cofix_one_body.
    rewrite -> (OnOne2_length X).
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + cbn. specialize (ih Γ0 Δ (Γ' ,,, fix_context mfix0)).
      rewrite app_context_assoc in ih.
      specialize (ih eq_refl wfΓ Hs).
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      rewrite app_context_length in ih.
      rewrite fix_context_length in ih.
      rewrite <- subst_fix_context in ih.
      rewrite <- (OnOne2_length X).
      eapply ih ; eauto.
    + cbn. f_equal.
Qed.

Lemma untyped_substlet_length  {Γ s Δ} : untyped_subslet Γ s Δ -> #|s| = #|Δ|.
Proof.
  induction 1; simpl; auto with arith.
Qed.

Lemma substitution_untyped_let_red {cf:checker_flags} Σ Γ Δ Γ' s M N :
  wf Σ -> untyped_subslet Γ s Δ ->
  red1 Σ (Γ ,,, Δ ,,, Γ') M N ->
  red Σ (Γ ,,, subst_context s 0 Γ') (subst s #|Γ'| M) (subst s #|Γ'| N).
Proof.
  intros wfΣ Hs H.
  remember (Γ ,,, Δ ,,, Γ') as Γ0. revert Γ Δ Γ' HeqΓ0 Hs.
  induction H using red1_ind_all in |- *; intros Γ0 Δ Γ' HeqΓ0 Hs; try subst Γ; cbn -[iota_red];
  match goal with
    |- context [iota_red _ _ _ _] => idtac
  | |- _ => autorewrite with subst
  end;
    try solve [ apply red1_red; econstructor; try inv wfM; eauto ].

  - pose proof (untyped_substlet_length Hs).
    elim (leb_spec_Set); intros Hn.
    + destruct (nth_error s) eqn:Heq.
      * pose proof (nth_error_Some_length Heq).
        rewrite -> nth_error_app_context_ge in H by lia.
        rewrite -> nth_error_app_context_lt in H by lia.
        destruct nth_error eqn:HΓ'. 2: noconf H.
        destruct c as [na [b|] ty]; noconf H.
        eapply untyped_subslet_nth_error in Heq; eauto. simpl in Heq.
        subst t.
        pose (commut_lift_subst_rec body (skipn (S (i - #|Γ'|)) s) #|Γ'| 0 0).
        forward e by lia. rewrite e.
        simpl. rewrite subst_skipn. 1: auto with arith.
        rewrite simpl_lift; auto with arith.
        assert(S (i - #|Γ'|) + #|Γ'| = S i) as -> by lia.
        constructor.
      * apply nth_error_None in Heq.
        assert(S i = #|s| + (S (i - #|s|))) by lia.
        rewrite H1. rewrite -> simpl_subst; try lia.
        apply red1_red.
        econstructor.
        rewrite nth_error_app_context_ge // in H.
        rewrite nth_error_app_context_ge // in H. 1: lia.
        rewrite -> nth_error_app_context_ge. 2:(autorewrite with wf; lia).
        rewrite <- H. f_equal. f_equal. autorewrite with wf. lia.
    + rewrite -> nth_error_app_context_lt in H by lia.
      pose (commut_lift_subst_rec body s (S i) (#|Γ'| - S i) 0).
      assert(eq:#|Γ'| - S i + S i = #|Γ'|) by lia.
      rewrite -> eq in e. rewrite <- e by lia.
      apply red1_red. constructor.
      rewrite -> nth_error_app_context_lt by (autorewrite with wf; lia).
      rewrite -> nth_error_subst_context.
      unfold subst_decl; now rewrite -> option_map_decl_body_map_decl, H, Nat.add_0_r.

  - rewrite subst_iota_red.
    autorewrite with subst.
    apply red1_red; constructor.

  - pose proof (subst_declared_constant _ _ _ s #|Γ'| u wfΣ H).
    apply (f_equal cst_body) in H1.
    rewrite <- !map_cst_body in H1. rewrite H0 in H1. simpl in H1.
    injection H1. intros ->. apply red1_red.
    econstructor. all: eauto.

  - simpl. apply red1_red; constructor.
    now rewrite nth_error_map H.

  - specialize (IHred1 Γ0 Δ Γ' eq_refl Hs).
    apply red_abs. 1: auto. constructor.

  - specialize (IHred1 Γ0 Δ (Γ' ,, _) eq_refl Hs).
    apply red_abs; auto with pcuic.
    now rewrite subst_context_snoc0 in IHred1.

  - specialize (IHred1 _ _ Γ' eq_refl Hs).
    apply red_letin; auto.

  - specialize (IHred1 _ _ Γ' eq_refl Hs).
    apply red_letin; auto.

  - specialize (IHred1 _ _ (Γ' ,, _) eq_refl Hs).
    apply red_letin; auto.
    now rewrite subst_context_snoc0 in IHred1.

  - simplify_IH_hyps. eapply red_case; auto.
    apply All2_map, All2_same. intros. split; auto.

  - simplify_IH_hyps. eapply red_case; auto.
    apply All2_map, All2_same. intros. split; auto.

  - simplify_IH_hyps. apply red_case; auto.
    eapply All2_map.
    eapply OnOne2_All2; eauto. simpl. intuition eauto.

  - apply red_proj_c. eauto.

  - apply red_app; eauto.

  - eapply red_app; eauto.

  - eapply red_prod; eauto.

  - eapply red_prod; eauto.
    specialize (IHred1 _ _ (_ ,, _) eq_refl Hs).
    simpl in IHred1. now rewrite subst_context_snoc0 in IHred1.

  - eapply red_evar; eauto.
    eapply All2_map. eapply OnOne2_All2; tea; cbnr.
    intuition.

  - eapply red_fix_one_ty.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    intros.
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_fix_one_body.
    rewrite -> (OnOne2_length X).
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + cbn. specialize (ih Γ0 Δ (Γ' ,,, fix_context mfix0)).
      rewrite app_context_assoc in ih.
      specialize (ih eq_refl).
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      rewrite app_context_length in ih.
      rewrite fix_context_length in ih.
      rewrite <- subst_fix_context in ih.
      rewrite <- (OnOne2_length X).
      eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_cofix_one_ty.
    rewrite -> (OnOne2_length X). generalize (#|mfix1|).
    intros.
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + eapply ih ; eauto.
    + cbn. f_equal.

  - eapply red_cofix_one_body.
    rewrite -> (OnOne2_length X).
    eapply OnOne2_map. eapply OnOne2_impl ; eauto.
    intros [? ? ? ?] [? ? ? ?] [[? ih] e]. simpl in *.
    inversion e. subst. clear e.
    split.
    + cbn. specialize (ih Γ0 Δ (Γ' ,,, fix_context mfix0)).
      rewrite app_context_assoc in ih.
      specialize (ih eq_refl).
      rewrite -> subst_context_app in *.
      rewrite -> app_context_assoc, Nat.add_0_r in *.
      rewrite app_context_length in ih.
      rewrite fix_context_length in ih.
      rewrite <- subst_fix_context in ih.
      rewrite <- (OnOne2_length X).
      eapply ih ; eauto.
    + cbn. f_equal.
Qed.

Lemma substitution_untyped_red {cf:checker_flags} Σ Γ Δ Γ' s M N :
  wf Σ -> untyped_subslet Γ s Δ ->
  red Σ (Γ ,,, Δ ,,, Γ') M N ->
  red Σ (Γ ,,, subst_context s 0 Γ') (subst s #|Γ'| M) (subst s #|Γ'| N).
Proof.
  intros wfΣ subsl.
  induction 1. 
  - constructor.
  - etransitivity.
    * eapply IHX.
    * eapply substitution_untyped_let_red; eauto.
Qed.

Lemma subst_eq_decl `{checker_flags} ϕ l k d d' :
  eq_decl ϕ d d' -> eq_decl ϕ (subst_decl l k d) (subst_decl l k d').
Proof.
  destruct d, d', decl_body, decl_body0;
    unfold eq_decl, map_decl; cbn; intuition auto using subst_eq_term.
Qed.

Lemma subst_eq_context `{checker_flags} φ l l' n k :
  eq_context φ l l' ->
  eq_context φ (subst_context n k l) (subst_context n k l').
Proof.
  induction l in l', n, k |- *; inversion 1. 1: constructor.
  rewrite !subst_context_snoc. constructor.
  - erewrite All2_length by eassumption.
    now apply subst_eq_decl.
  - now apply IHl.
Qed.

Lemma substitution_red `{cf : checker_flags} (Σ : global_env_ext) Γ Δ Γ' s M N :
  wf Σ -> subslet Σ Γ s Δ -> wf_local Σ Γ ->
  red Σ (Γ ,,, Δ ,,, Γ') M N ->
  red Σ (Γ ,,, subst_context s 0 Γ') (subst s #|Γ'| M) (subst s #|Γ'| N).
Proof.
  intros HG Hs Hl Hred. induction Hred. 1: constructor.
  eapply red_trans with (subst s #|Γ'| P); auto.
  eapply substitution_let_red; eauto.
Qed.

Lemma red_red {cf:checker_flags} (Σ : global_env) Γ Γ' s s' b : wf Σ ->
  All2 (red Σ Γ) s s' ->
  red Σ (Γ ,,, Γ') (subst s #|Γ'| b) (subst s' #|Γ'| b).
Proof.
  intros wfΣ Hall.
  revert Γ'.
  elim b using term_forall_list_ind;
        intros; match goal with
                  |- context [tRel _] => idtac
                | |- _ => cbn -[plus]
                end; try easy;
      rewrite -> ?map_map_compose, ?compose_on_snd, ?compose_map_def, ?map_length, ?Nat.add_assoc;
      try solve [f_equal; auto; solve_all].

  - unfold subst.
    destruct (#|Γ'| <=? n) eqn:Heq.
    + destruct nth_error eqn:Heq'.
      * destruct (All2_nth_error_Some _ _ Hall Heq') as [t' [-> Ptt']].
        intros. apply (weakening_red Σ Γ [] Γ' t t'); auto.
      * rewrite (All2_nth_error_None _ Hall Heq').
        apply All2_length in Hall as ->. constructor.
    + constructor.

  - apply red_evar. apply All2_map. solve_all.
  - apply red_prod; eauto.
    now eapply (X0 (Γ' ,, _)).

  - apply red_abs; eauto.
    now eapply (X0 (Γ' ,, _)).

  - apply red_letin; eauto.
    now eapply (X1 (Γ' ,, _)).

  - apply red_app; eauto.
  - apply red_case; eauto.
    unfold on_Trel in *; solve_all.
  - apply red_proj_c; eauto.
  - apply red_fix_congr; eauto.
    solve_all.
    rewrite subst_fix_context.
    specialize (b0 (Γ' ,,, subst_context s #|Γ'| (fix_context m))).
    now rewrite app_context_length subst_context_length app_context_assoc fix_context_length in b0.
  - apply red_cofix_congr; eauto.
    red in X. solve_all.
    rewrite subst_fix_context.
    specialize (b0 (Γ' ,,, subst_context s #|Γ'| (fix_context m))).
    now rewrite app_context_length subst_context_length app_context_assoc fix_context_length in b0.
Qed.

Lemma untyped_substitution_red {cf:checker_flags} Σ Γ Δ Γ' s M N :
  wf Σ -> untyped_subslet Γ s Δ ->
  red Σ (Γ ,,, Δ ,,, Γ') M N ->
  red Σ (Γ ,,, subst_context s 0 Γ') (subst s #|Γ'| M) (subst s #|Γ'| N).
Proof.
  intros HG Hs Hred. induction Hred. 1: constructor.
  eapply red_trans with (subst s #|Γ'| P); auto.
  eapply substitution_untyped_let_red; eauto.
Qed.

(** The cumulativity relation is substitutive, yay! *)

Fixpoint subst_stack s k π :=
  match π with
  | ε => ε
  | App u π =>
      let k' := #|stack_context π| + k in
      App (subst s k' u) (subst_stack s k π)
  | Fix mfix idx args π =>
      let k' := #|stack_context π| + k in
      let k'' := #|mfix| + k' in
      let mfix' := List.map (map_def (subst s k') (subst s k'')) mfix in
      Fix mfix' idx (map (subst s k') args) (subst_stack s k π)
  | Fix_mfix_ty na bo ra mfix1 mfix2 idx π =>
      let k' := #|stack_context π| + k in
      let k'' := #|mfix1| + S #|mfix2| + k' in
      let mfix1' := List.map (map_def (subst s k') (subst s k'')) mfix1 in
      let mfix2' := List.map (map_def (subst s k') (subst s k'')) mfix2 in
      Fix_mfix_ty na (subst s k'' bo) ra mfix1' mfix2' idx (subst_stack s k π)
  | Fix_mfix_bd na ty ra mfix1 mfix2 idx π =>
      let k' := #|stack_context π| + k in
      let k'' := #|mfix1| + S #|mfix2| + k' in
      let mfix1' := List.map (map_def (subst s k') (subst s k'')) mfix1 in
      let mfix2' := List.map (map_def (subst s k') (subst s k'')) mfix2 in
      Fix_mfix_bd na (subst s k' ty) ra mfix1' mfix2' idx (subst_stack s k π)
  | CoFix mfix idx args π =>
      let k' := #|stack_context π| + k in
      let k'' := #|mfix| + k' in
      let mfix' := List.map (map_def (subst s k') (subst s k'')) mfix in
      CoFix mfix' idx (map (subst s k') args) (subst_stack s k π)
  | Case_p indn c brs π =>
      let k' := #|stack_context π| + k in
      let brs' := List.map (on_snd (subst s k')) brs in
      Case_p indn (subst s k' c) brs' (subst_stack s k π)
  | Case indn pred brs π =>
      let k' := #|stack_context π| + k in
      let brs' := List.map (on_snd (subst s k')) brs in
      Case indn (subst s k' pred) brs' (subst_stack s k π)
  | Case_brs indn pred c m brs1 brs2 π =>
      let k' := #|stack_context π| + k in
      let brs1' := List.map (on_snd (subst s k')) brs1 in
      let brs2' := List.map (on_snd (subst s k')) brs2 in
      Case_brs indn (subst s k' pred) (subst s k' c) m brs1' brs2' (subst_stack s k π)
  | Proj p π =>
      Proj p (subst_stack s k π)
  | Prod_l na B π =>
      let k' := #|stack_context π| + k in
      Prod_l na (subst s (S k') B) (subst_stack s k π)
  | Prod_r na A π =>
      let k' := #|stack_context π| + k in
      Prod_r na (subst s k' A) (subst_stack s k π)
  | Lambda_ty na b π =>
      let k' := #|stack_context π| + k in
      Lambda_ty na (subst s (S k') b) (subst_stack s k π)
  | Lambda_tm na A π =>
      let k' := #|stack_context π| + k in
      Lambda_tm na (subst s k' A) (subst_stack s k π)
  | LetIn_bd na B u π =>
      let k' := #|stack_context π| + k in
      LetIn_bd na (subst s k' B) (subst s (S k') u) (subst_stack s k π)
  | LetIn_ty na b u π =>
      let k' := #|stack_context π| + k in
      LetIn_ty na (subst s k' b) (subst s (S k') u) (subst_stack s k π)
  | LetIn_in na b B π =>
      let k' := #|stack_context π| + k in
      LetIn_in na (subst s k' b) (subst s k' B) (subst_stack s k π)
  | coApp u π =>
      let k' := #|stack_context π| + k in
      coApp (subst s k' u) (subst_stack s k π)
  end.

Lemma subst_zipc :
  forall s k t π,
    let k' := #|stack_context π| + k in
    subst s k (zipc t π) =
    zipc (subst s k' t) (subst_stack s k π).
Proof.
  intros s k t π k'.
  induction π in s, k, t, k' |- *.
  all: try reflexivity.
  all: try solve [
    simpl ; rewrite IHπ ; cbn ; reflexivity
  ].
  - simpl. rewrite IHπ. cbn. f_equal.
    rewrite subst_mkApps. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. rewrite !app_length. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. rewrite !app_length. cbn. f_equal.
    unfold map_def at 1. cbn. f_equal.
    rewrite fix_context_alt_length.
    rewrite !app_length. cbn. rewrite !map_length.
    f_equal. f_equal. lia.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite subst_mkApps. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. cbn. reflexivity.
Qed.

Lemma eta1_subst s k u v :
  eta1 u v -> eta1 (subst s k u) (subst s k v).
Proof.
  induction 1 in k |- *  using eta1_ind_all; cbn;
    try (constructor; auto; fail).
  - refine (transport (fun x => eta1 x _) _ (eta_red _ _ _)). do 2 f_equal.
    symmetry; apply  commut_lift_subst.
  - constructor. eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros [] [] [[] ?]; cbn in *. split; auto.
  - constructor. eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros ? ? []; auto.
  - constructor. apply OnOne2_length in X as e. rewrite e.
    eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros [] [] [[] ?]; cbn in *.
    invs e2; split; auto.
  - apply fix_eta_body. apply OnOne2_length in X as e. rewrite e.
    eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros [] [] [[] ?]; cbn in *.
    invs e2; split; auto.
  - constructor. apply OnOne2_length in X as e. rewrite e.
    eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros [] [] [[] ?]; cbn in *.
    invs e2; split; auto.
  - apply cofix_eta_body. apply OnOne2_length in X as e. rewrite e.
    eapply OnOne2_map, OnOne2_impl; tea; cbn.
    intros [] [] [[] ?]; cbn in *.
    invs e2; split; auto.
Defined.

Lemma eta_subst s k u v :
  eta u v -> eta (subst s k u) (subst s k v).
Proof.
  induction 1; [econstructor 1|econstructor 2|econstructor 3];
    eauto using eta1_subst.
Defined.


(* todo remove All2_nth_error_Some_r and All2_nth_error ?? *)
Lemma subst_eta s s' k b :
  All2 eta s s' -> eta (subst s k b) (subst s' k b).
Proof.
  induction b in s, s', k |- * using term_forall_list_ind; cbn; intro XX.
  2, 4-11, 13: eauto with eta.
  - destruct (leb_spec_Set k n); eauto with eta.
    rewrite (All2_length _ _ XX).
    destruct (nth_error s (n - k)) eqn:X.
    + eapply All2_nth_error_Some in X; tea.
      destruct X as [? [X1 X2]]; rewrite X1.
      now apply weakening_eta.
    + eapply All2_nth_error_None in X; tea.
      now rewrite X.
  - eapply eta_Evar. eapply All2_map, All_All2; eauto.
  - eapply eta_Case; eauto. eapply All2_map, All_All2; cbn; eauto.
  - eapply eta_Fix; eauto. eapply All2_map, All_All2; tea; cbn.
    clear -XX. intros x [H1 H2]. rdest; eauto.
  - eapply eta_CoFix; eauto. eapply All2_map, All_All2; tea; cbn.
    clear -XX. intros x [H1 H2]. rdest; eauto.
Defined.

Lemma substitution_upto_domain u v :
  upto_domain u v -> forall s k, upto_domain (subst s k u) (subst s k v).
Proof.
  induction u in v |- * using term_forall_list_ind;
    intro e; invs e; cbn; try reflexivity; constructor; eauto.
  1-2: solve_all.
  all: rewrite (All2_length _ _ X0); solve_all.
Qed.

Lemma substitution_untyped_cumul {cf:checker_flags} Σ Γ Γ' Γ'' s M N :
  wf Σ.1 -> untyped_subslet Γ s Γ' ->
  Σ ;;; Γ ,,, Γ' ,,, Γ'' |- M <= N ->
  Σ ;;; Γ ,,, subst_context s 0 Γ'' |- subst s #|Γ''| M <= subst s #|Γ''| N.
Proof.
  intros wfΣ Hs. induction 1.
  - econstructor.
    + apply subst_leq_term; eassumption.
    + now apply substitution_upto_domain.
  - eapply substitution_untyped_let_red in r. 3:eauto. all:eauto with wf.
    eapply red_cumul_cumul; eauto.
  - eapply substitution_untyped_let_red in r. 3:eauto. all:eauto with wf.
    eapply red_cumul_cumul_inv; eauto.
  - eapply cumul_eta_l. 2: eassumption.
    eapply eta1_subst. assumption.
  - eapply cumul_eta_r. 1: eassumption.
    eapply eta1_subst. assumption.
Qed.

Lemma substitution_cumul0 {cf:checker_flags} Σ Γ na t u u' a : wf Σ.1 ->
  Σ ;;; Γ ,, vass na t |- u <= u' ->
  Σ ;;; Γ |- subst10 a u <= subst10 a u'.
Proof.
  move=> wfΣ Hu.
  pose proof (substitution_untyped_cumul Σ Γ [vass na t] [] [a] u u' wfΣ).
  forward X.
  { constructor. constructor. }
  simpl in X. now apply X.
Qed.

Lemma substitution_cumul_let {cf:checker_flags} Σ Γ na t ty u u' : wf Σ.1 ->
  Σ ;;; Γ ,, vdef na t ty |- u <= u' ->
  Σ ;;; Γ |- subst10 t u <= subst10 t u'.
Proof.
  move=> wfΣ Hu.
  pose proof (substitution_untyped_cumul Σ Γ [vdef na t ty] [] [t] u u' wfΣ).
  forward X.
  { rewrite - {1}(subst_empty 0 t). constructor. constructor. }
  simpl in X. now apply X.
Qed.

(** The cumulativity relation is substitutive, yay! *)

Lemma substitution_cumul `{cf : checker_flags} (Σ : global_env_ext) Γ Γ' Γ'' s M N :
  wf Σ -> wf_local Σ (Γ ,,, Γ' ,,, Γ'') -> subslet Σ Γ s Γ' ->
  Σ ;;; Γ ,,, Γ' ,,, Γ'' |- M <= N ->
  Σ ;;; Γ ,,, subst_context s 0 Γ'' |- subst s #|Γ''| M <= subst s #|Γ''| N.
Proof.
  intros wfΣ wfΓ Hs. induction 1.
  - econstructor.
    + apply subst_leq_term; eassumption.
    + now eapply substitution_upto_domain.
  - eapply substitution_let_red in r. 4:eauto. all:eauto with wf.
    eapply red_cumul_cumul; eauto.
  - eapply substitution_let_red in r. 4:eauto. all:eauto with wf.
    eapply red_cumul_cumul_inv; eauto.
  - eapply cumul_eta_l. 2: eassumption.
    eapply eta1_subst. assumption.
  - eapply cumul_eta_r. 1: eassumption.
    eapply eta1_subst. assumption.
Qed.

(** Old substitution lemma without lets *)
(*
Theorem substitution Σ Γ Γ' s Δ (t : term) T :
  wf Σ -> subs Σ Γ s Γ' ->
  Σ ;;; Γ ,,, Γ' ,,, Δ |- t : T ->
  wf_local Σ (Γ ,,, subst_context s 0 Δ) ->
  Σ ;;; Γ ,,, subst_context s 0 Δ |- subst s #|Δ| t : subst s #|Δ| T.
Proof.
  intros HΣ Hs Ht.
  pose proof (typing_wf_local Ht).
  generalize_eqs Ht. intros eqw. rewrite <- eqw in X.
  revert Γ Γ' Δ s Hs eqw.
  revert Σ HΣ Γ0 X t T Ht.
  apply (typing_ind_env (fun Σ Γ0 t T =>
  forall (Γ Γ' Δ : context) (s : list term)
    (sub : subs Σ Γ s Γ') (eqΓ0 : Γ0 = Γ ,,, Γ' ,,, Δ)
    (wfsubs : wf_local Σ (Γ ,,, subst_context s 0 Δ)),
    Σ ;;; Γ ,,, subst_context s 0 Δ |- subst s #|Δ| t : subst s #|Δ| T));
    intros Σ wfΣ Γ0 wfΓ0; intros; subst Γ0; simpl in *; try solve [econstructor; eauto].

  - elim (leb_spec_Set); intros Hn.
    elim nth_error_spec.
    + intros x Heq Hlt.
      pose proof (subst_length _ _ _ _ sub).
      rewrite -> nth_error_app_context_ge in H by lia.
      rewrite -> nth_error_app_context_lt in H by lia.
      eapply subs_nth_error in Heq; eauto.
      destruct decl_body; try contradiction.
      cbn -[skipn] in Heq.
      eapply refine_type.
      eapply (weakening _ _ (subst_context s 0 Δ)) in Heq; eauto with wf.
      rewrite subst_context_length in Heq. eapply Heq.
      rewrite -> commut_lift_subst_rec by lia.
      rewrite <- (firstn_skipn (S (n - #|Δ|)) s) at 2.
      rewrite -> subst_app_decomp. f_equal.
      replace (S n) with ((S n - #|Δ|) + #|Δ|) by lia.
      assert (eq:#|(map (lift0 #|skipn (S (n - #|Δ|)) s|) (firstn (S (n - #|Δ|)) s))| = S n - #|Δ|).
      rewrite map_length. rewrite -> firstn_length by lia. lia.
      rewrite <- eq. rewrite -> simpl_subst_rec; auto; try lia.

    + intros Hs.
      pose proof (subst_length _ _ _ _ sub).
      rewrite H0 in Hs.
      assert (S n = #|s| + (S (n - #|s|))) by lia.
      rewrite H1. rewrite simpl_subst; auto; try lia.
      constructor; auto.
      rewrite -> nth_error_app_context_ge; try lia; rewrite subst_context_length.
      rewrite -> 2!nth_error_app_context_ge in H by lia.
      rewrite <- H. f_equal. lia.
      lia.

    + eapply subs_nth_error_lt in sub; eauto.
      rewrite H in sub. simpl in sub.
      eapply refine_type. constructor; eauto.
      rewrite <- map_decl_type.
      rewrite -> commut_lift_subst_rec by lia.
      f_equal. lia.

  - econstructor; auto. eapply X1; eauto.
    specialize (X1 Γ Γ' Δ s sub eq_refl wfsubs).
    specialize (X3 Γ Γ' (Δ,, vass n t) s sub eq_refl).
    rewrite subst_context_snoc0 in X3. forward X3.
    now econstructor; simpl; eauto.
    eapply X3.

  - econstructor; auto. eapply X1; eauto.
    specialize (X1 Γ Γ' Δ s sub eq_refl wfsubs).
    specialize (X3 Γ Γ' (Δ,, vass n t) s sub eq_refl).
    rewrite subst_context_snoc0 in X3. forward X3.
    now econstructor; simpl; eauto.
    eapply X3.

  - specialize (X1 Γ Γ' Δ s sub eq_refl wfsubs).
    specialize (X3 Γ Γ' Δ s sub eq_refl wfsubs).
    specialize (X5 Γ Γ' (Δ,, vdef n b b_ty) s sub eq_refl).
    rewrite subst_context_snoc0 in X5. forward X5.
    now econstructor; simpl; eauto.
    econstructor; eauto.

  - specialize (X1 Γ Γ' Δ s sub eq_refl wfsubs).
    eapply refine_type. econstructor; eauto.
    unfold subst1. rewrite -> distr_subst. simpl. reflexivity.

  - eapply refine_type. constructor; eauto.
    rewrite !map_cst_type. eapply subst_declared_constant in H as ->; eauto.

  - eapply refine_type. econstructor; eauto.
    eapply on_declared_inductive in isdecl as [on_mind on_ind]; auto.
    apply onArity in on_ind as [[s' Hindty] _].
    apply typecheck_closed in Hindty as [_ Hindty]; eauto. symmetry.
    move/andP/proj1: Hindty. rewrite -(closedn_subst_instance_constr _ _ u) => Hty.
    apply: (subst_closedn s #|Δ|); auto with wf.
    eapply closed_upwards. eauto. simpl; lia.

  - eapply refine_type. econstructor; eauto.
    symmetry.
    apply on_declared_constructor in isdecl as [_ onc]; auto.
    eapply on_constructor_closed in onc as clty; auto.
    unfold type_of_constructor.
    apply subst_closedn; eauto. eapply closed_upwards; eauto. lia.

  - rewrite subst_mkApps map_app map_skipn.
    specialize (X2 Γ Γ' Δ s sub eq_refl wfsubs).
    specialize (X4 Γ Γ' Δ s sub eq_refl wfsubs).
    simpl. econstructor.
    4:{ eapply subst_types_of_case in H0.
        simpl in H1. subst pars. rewrite firstn_map. eapply H0; eauto.
        all:eauto. }
    -- eauto.
    -- eauto.
    -- eauto.
    -- revert H1. subst pars.
       apply subst_check_correct_arity.
    -- destruct idecl; simpl in *; auto.
    -- now rewrite !subst_mkApps in X4.
    -- solve_all.

  - specialize (X2 Γ Γ' Δ s sub eq_refl wfsubs).
    eapply refine_type. econstructor.
    eauto.
    rewrite subst_mkApps in X2. eauto.
    rewrite map_length; eauto.
    rewrite <- (Nat.add_0_l #|Δ|).
    erewrite distr_subst_rec. simpl.
    rewrite map_rev. subst ty.
    f_equal.
    apply on_declared_projection in isdecl as [_ isdecl]; auto.
    eapply on_projection_closed in isdecl as clty; auto.
    symmetry. apply subst_closedn; eauto.
    rewrite List.rev_length H. eapply closed_upwards; eauto. lia.

  - assert (wf_local Σ (Γ ,,, subst_context s 0 Δ ,,, subst_context s #|Δ| (fix_context mfix))).
    subst types.
    apply All_local_env_app in X as [X Hfixc].
    apply All_local_env_app_inv. intuition.
    revert Hfixc. clear X0 X H.
    induction 1; simpl; auto.
    + destruct t0 as [u [Ht IHt]].
      specialize (IHt Γ Γ' (Δ ,,, Γ0) s sub). forward IHt. now rewrite app_context_assoc.
      rewrite app_context_length subst_context_app app_context_assoc Nat.add_0_r in IHt.
      unfold snoc; rewrite subst_context_snoc; econstructor; auto. exists u.
        apply IHt; apply All_local_env_app_inv; intuition.
    + destruct t0 as [Ht IHt].
       specialize (IHt Γ Γ' (Δ ,,, Γ0) s sub). forward IHt. now rewrite app_context_assoc.
       rewrite app_context_length subst_context_app app_context_assoc Nat.add_0_r in IHt.
       unfold snoc; rewrite subst_context_snoc; econstructor; auto;
       apply IHt; apply All_local_env_app_inv; intuition.
    + erewrite map_dtype. eapply type_Fix.
      * rewrite nth_error_map H. reflexivity.
      * now rewrite subst_fix_context.
      * rewrite subst_fix_context.
        apply All_map.
        clear X. eapply All_impl; eauto.
        clear X0. simpl; intros [na ty bod] [[Htyd Hlam] IH].
        simpl in *. intuition.
        specialize (IH Γ Γ' (Δ ,,, fix_context mfix) s sub).
        forward IH by now rewrite app_context_assoc.
        rewrite subst_context_app in IH.
        subst types.
        rewrite !app_context_assoc Nat.add_0_r !app_context_length fix_context_length in IH.
        specialize (IH X1).
        rewrite subst_context_length fix_context_length.
        rewrite commut_lift_subst_rec. lia. now rewrite (Nat.add_comm #|Δ|).
        now apply isLambda_subst.

  - assert (wf_local Σ (Γ ,,, subst_context s 0 Δ ,,, subst_context s #|Δ| (fix_context mfix))).
    subst types.
    apply All_local_env_app in X as [X Hfixc].
    apply All_local_env_app_inv. intuition.
    revert Hfixc. clear X0 X H.
    induction 1; simpl; auto.
    + destruct t0 as [u [Ht IHt]].
      specialize (IHt Γ Γ' (Δ ,,, Γ0) s sub). forward IHt. now rewrite app_context_assoc.
      rewrite app_context_length subst_context_app app_context_assoc Nat.add_0_r in IHt.
      unfold snoc; rewrite subst_context_snoc; econstructor; auto. exists u.
        apply IHt; apply All_local_env_app_inv; intuition.
    + destruct t0 as [Ht IHt].
       specialize (IHt Γ Γ' (Δ ,,, Γ0) s sub). forward IHt. now rewrite app_context_assoc.
       rewrite app_context_length subst_context_app app_context_assoc Nat.add_0_r in IHt.
       unfold snoc; rewrite subst_context_snoc; econstructor; auto;
       apply IHt; apply All_local_env_app_inv; intuition.
    + erewrite map_dtype. eapply type_CoFix.
      * rewrite nth_error_map H. reflexivity.
      * now rewrite subst_fix_context.
      * rewrite subst_fix_context.
        apply All_map.
        clear X. eapply All_impl; eauto.
        clear X0. simpl; intros [na ty bod] [Htyd IH].
        simpl in *. intuition.
        specialize (IH Γ Γ' (Δ ,,, fix_context mfix) s sub).
        forward IH by now rewrite app_context_assoc.
        rewrite subst_context_app in IH.
        subst types.
        rewrite !app_context_assoc Nat.add_0_r !app_context_length fix_context_length in IH.
        specialize (IH X1).
        rewrite subst_context_length fix_context_length.
        rewrite commut_lift_subst_rec. lia.
        now rewrite (Nat.add_comm #|Δ|).

  - econstructor; eauto.
    destruct X2 as [Bs|[u Hu]].
    + left. destruct Bs as [[ctx [u [Hd IH]]]]. simpl in *.
      exists (subst_context s #|Δ| ctx), u.
      pose proof (subst_destArity [] B s #|Δ|). rewrite Hd in H.
      rewrite H. clear H.
      split; auto.
      apply All_local_env_app_inv; intuition auto.
      clear -sub wfsubs a.
      induction ctx; try constructor; depelim a.
      -- rewrite subst_context_snoc.
         unfold snoc. unfold vass, snoc in H. noconf H.
         econstructor; auto.
         eapply IHctx. eapply a.
         simpl. destruct tu as [u tu]. exists u.
         specialize (t0 _ _ (Δ ,,, ctx) _ sub). forward t0.
         now rewrite app_context_assoc. simpl in t0.
         forward t0. rewrite subst_context_app app_context_assoc Nat.add_0_r.
         apply All_local_env_app_inv. split; auto.
         eapply IHctx. eapply a.
         now rewrite subst_context_app Nat.add_0_r app_context_assoc app_length in t0.
      -- rewrite subst_context_snoc.
         unfold vdef, snoc in H |- *. noconf H.
         constructor; auto.
         eapply IHctx. eapply a.
         simpl.
         specialize (t0 _ _ (Δ ,,, ctx) _ sub). forward t0.
         now rewrite app_context_assoc. simpl in t0.
         forward t0. rewrite subst_context_app app_context_assoc Nat.add_0_r.
         apply All_local_env_app_inv. split; auto.
         eapply IHctx. eapply a.
         now rewrite subst_context_app Nat.add_0_r app_context_assoc app_length in t0.
    + right; exists u; intuition eauto.
    + eapply substitution_cumul; eauto.
Qed.
*)

Theorem substitution_prop `{cf : checker_flags} : env_prop
  (fun Σ Γ0 t T =>
  forall (Γ Γ' Δ : context) (s : list term)
    (sub : subslet Σ Γ s Γ') (eqΓ0 : Γ0 = Γ ,,, Γ' ,,, Δ),
    Σ ;;; Γ ,,, subst_context s 0 Δ |- subst s #|Δ| t : subst s #|Δ| T)
  (fun Σ Γ0 _ =>
    forall (Γ Γ' Δ : context) (s : list term)
    (sub : subslet Σ Γ s Γ') (eqΓ0 : Γ0 = Γ ,,, Γ' ,,, Δ),
    wf_local Σ (Γ ,,, subst_context s 0 Δ)).
Proof.
  apply typing_ind_env;
  intros Σ wfΣ Γ0 wfΓ0; intros; subst Γ0; simpl in *; try solve [econstructor; eauto];
    try specialize (X _ _ _ _ sub eq_refl).


  - induction Δ.
    + clear X. simpl in *.  now apply All_local_env_app in wfΓ0.
    + rewrite subst_context_snoc.
      depelim X; unfold snoc in H; noconf H; simpl;
      econstructor; eauto.
      * exists (tu.π1). rewrite Nat.add_0_r; now eapply t0.
      * exists (tu.π1). rewrite Nat.add_0_r; now eapply t1.
      * rewrite Nat.add_0_r; now eapply t0.
      
  - elim (leb_spec_Set); intros Hn.
    + elim nth_error_spec.
      * intros x Heq Hlt.
        pose proof (subslet_length sub).
        rewrite -> nth_error_app_context_ge in H by lia.
        rewrite -> nth_error_app_context_lt in H by lia.
        eapply subslet_nth_error in Heq; eauto.
        destruct decl_body;
        cbn -[skipn] in Heq.

        -- intuition. subst x.
           eapply refine_type.
           ++ eapply (weakening _ _ (subst_context s 0 Δ)) in b; eauto with wf.
              rewrite subst_context_length in b. eapply b.
           ++ rewrite -> commut_lift_subst_rec by lia.
              rewrite <- (firstn_skipn (S (n - #|Δ|)) s) at 2.
              rewrite -> subst_app_decomp. f_equal.
              replace (S n) with ((S n - #|Δ|) + #|Δ|) by lia.
              assert (eq:#|(map (lift0 #|skipn (S (n - #|Δ|)) s|) (firstn (S (n - #|Δ|)) s))| = S n - #|Δ|).
              { rewrite map_length. rewrite -> firstn_length by lia. lia. }
              rewrite <- eq. rewrite -> simpl_subst_rec; auto; try lia.

        -- eapply refine_type.
           ++ eapply (weakening _ _ (subst_context s 0 Δ)) in Heq; eauto with wf.
              rewrite subst_context_length in Heq. eapply Heq.
           ++ rewrite -> commut_lift_subst_rec by lia.
              rewrite <- (firstn_skipn (S (n - #|Δ|)) s) at 2.
              rewrite -> subst_app_decomp. f_equal.
              replace (S n) with ((S n - #|Δ|) + #|Δ|) by lia.
              assert (eq:#|(map (lift0 #|skipn (S (n - #|Δ|)) s|) (firstn (S (n - #|Δ|)) s))| = S n - #|Δ|).
              { rewrite map_length. rewrite -> firstn_length by lia. lia. }
              rewrite <- eq. rewrite -> simpl_subst_rec; auto; try lia.

      * intros Hs.
        pose proof (subslet_length sub).
        rewrite H0 in Hs.
        assert (S n = #|s| + (S (n - #|s|))) by lia.
        rewrite H1. rewrite simpl_subst; auto; try lia.
        constructor; auto.
        rewrite -> nth_error_app_context_ge; try lia; rewrite -> subst_context_length.
        2: lia.
        rewrite -> 2!nth_error_app_context_ge in H by lia.
        rewrite <- H. f_equal. lia.

    + eapply subslet_nth_error_lt in sub; eauto.
      rewrite H in sub. simpl in sub.
      eapply refine_type.
      * constructor; eauto.
      * rewrite <- map_decl_type.
        rewrite -> commut_lift_subst_rec by lia.
        f_equal. lia.

  - econstructor; auto.
    + eapply X1; eauto.
    + specialize (X1 Γ Γ' Δ s sub eq_refl).
      specialize (X3 Γ Γ' (Δ,, vass n t) s sub eq_refl).
      now rewrite subst_context_snoc0 in X3.

  - econstructor; auto. 1: eapply X1; eauto.
    specialize (X1 Γ Γ' Δ s sub eq_refl).
    specialize (X3 Γ Γ' (Δ,, vass n t) s sub eq_refl).
    now rewrite subst_context_snoc0 in X3.

  - specialize (X1 Γ Γ' Δ s sub eq_refl).
    specialize (X3 Γ Γ' Δ s sub eq_refl).
    specialize (X5 Γ Γ' (Δ,, vdef n b b_ty) s sub eq_refl).
    rewrite subst_context_snoc0 in X5.
    econstructor; eauto.

  - specialize (X1 Γ Γ' Δ s sub eq_refl).
    eapply refine_type. 1: econstructor; eauto.
    unfold subst1. rewrite -> distr_subst. simpl. reflexivity.

  - eapply refine_type. 1: constructor; eauto.
    rewrite !map_cst_type. eapply subst_declared_constant in H as ->; eauto.

  - eapply refine_type. 1: econstructor; eauto.
    eapply on_declared_inductive in isdecl as [on_mind on_ind]; auto.
    apply onArity in on_ind as [s' Hindty].
    apply typecheck_closed in Hindty as [_ Hindty]; eauto. symmetry.
    move/andP/proj1: Hindty. rewrite -(closedn_subst_instance_constr _ _ u) => Hty.
    apply: (subst_closedn s #|Δ|); auto with wf.
    eapply closed_upwards. 1: eauto. simpl; lia.

  - eapply refine_type. 1: econstructor; eauto.
    symmetry.
    destruct (on_declared_constructor wfΣ isdecl) as [? [cs [? onc]]].
    eapply on_constructor_closed in onc as clty; auto.
    unfold type_of_constructor.
    apply subst_closedn; eauto. eapply closed_upwards; eauto. lia.

  - rewrite subst_mkApps map_app map_skipn.
    specialize (X2 Γ Γ' Δ s sub eq_refl).
    specialize (X4 Γ Γ' Δ s sub eq_refl).
    assert (Hclos: closed_ctx (ind_params mdecl)). {
      destruct isdecl as [Hmdecl Hidecl].
      eapply on_declared_minductive in Hmdecl; eauto.
      eapply onParams in Hmdecl.
      eapply closed_wf_local in Hmdecl; eauto. }
    assert (Hclos': closed (ind_type idecl)). {
      eapply on_declared_inductive in isdecl; eauto.
      destruct isdecl as [_ oind]. clear -oind wfΣ.
      apply onArity in oind; destruct oind as [s HH]; cbn in *.
      apply typecheck_closed in HH; eauto.
      apply snd in HH. apply andP in HH; apply HH. }
    simpl. econstructor. all: eauto.
    + eapply subst_build_case_predicate_type in H0; tea.
      * simpl in *. subst params. rewrite firstn_map.
        etransitivity; [|eapply H0; eauto]. f_equal.
        now erewrite subst_declared_inductive.
      * now rewrite closedn_subst_instance_context.
    + now rewrite !subst_mkApps in X4.
    + simpl.
      destruct (on_declared_inductive wfΣ isdecl) as [oind obod].
      pose obod.(onConstructors) as onc.
      eapply (subst_build_branches_type s #|Δ|) in H3; eauto.
      * subst params. rewrite firstn_map. exact H3.
      * now rewrite closedn_subst_instance_context.
    + solve_all.

  - specialize (X2 Γ Γ' Δ s sub eq_refl).
    eapply refine_type.
    + econstructor.
      * eauto.
      * rewrite subst_mkApps in X2. eauto.
      * rewrite map_length; eauto.
    + rewrite <- (Nat.add_0_l #|Δ|).
      erewrite distr_subst_rec. simpl.
      rewrite map_rev. subst ty.
      f_equal.
      eapply declared_projection_closed in isdecl; auto.
      symmetry; apply subst_closedn; eauto.
      rewrite List.rev_length H. rewrite closedn_subst_instance_constr.
      eapply closed_upwards; eauto. lia.

  - rewrite -> (map_dtype _ (subst s (#|mfix| + #|Δ|))).
    eapply type_Fix; auto.
    * eapply fix_guard_subst ; eauto.
    * now rewrite -> nth_error_map, H0.
    * eapply All_map.
      eapply (All_impl X0); simpl.
      intros x [u [Hs Hs']]; exists u.
      now specialize (Hs' _ _ _ _ sub eq_refl).
    * eapply All_map.
      eapply (All_impl X1); simpl.
      intros x [[Hb Hlam] IH].
      rewrite subst_fix_context.
      specialize (IH Γ Γ' (Δ ,,,  (fix_context mfix)) _ sub).
      rewrite app_context_assoc in IH. specialize (IH eq_refl).
      split; auto.
      + rewrite subst_context_app Nat.add_0_r app_context_assoc in IH.
        rewrite app_context_length fix_context_length in IH.
        rewrite subst_context_length fix_context_length.
        rewrite commut_lift_subst_rec; try lia. now rewrite (Nat.add_comm #|Δ|).
      + now rewrite isLambda_subst.
    * move: H1.
      rewrite /wf_fixpoint.
      pose proof (substitution_check_one_fix s #|Δ| mfix).
      destruct map_option_out eqn:Heq => //.
      specialize (H1 _ eq_refl).
      rewrite map_map_compose. now rewrite H1.

  - rewrite -> (map_dtype _ (subst s (#|mfix| + #|Δ|))).
    eapply type_CoFix; auto.
    * eapply cofix_guard_subst; auto.
    * now rewrite -> nth_error_map, H0.
    * eapply All_map.
      eapply (All_impl X0); simpl.
      intros x [u [Hs Hs']]; exists u.
      now specialize (Hs' _ _ _ _ sub eq_refl).
    * eapply All_map.
      eapply (All_impl X1); simpl.
      intros x [Hb IH].
      rewrite subst_fix_context.
      specialize (IH Γ Γ' (Δ ,,,  (fix_context mfix)) _ sub).
      rewrite app_context_assoc in IH. specialize (IH eq_refl).
      rewrite subst_context_app Nat.add_0_r app_context_assoc in IH.
      rewrite app_context_length fix_context_length in IH.
      rewrite subst_context_length fix_context_length.
      rewrite commut_lift_subst_rec; try lia. now rewrite (Nat.add_comm #|Δ|).      
    * move: H1.
      rewrite /wf_cofixpoint.
      pose proof (substitution_check_one_cofix s #|Δ| mfix).
      destruct map_option_out eqn:Heq => //.
      specialize (H1 _ eq_refl).
      rewrite map_map_compose. now rewrite H1.

  - econstructor; eauto.
    + destruct X2 as [Bs|[u Hu]].
      * left. destruct Bs as [[ctx [u [Hd IH]]]]. simpl in *.
        exists (subst_context s #|Δ| ctx), u.
        pose proof (subst_destArity [] B s #|Δ|). rewrite Hd in H.
        rewrite {}H.
        split; auto.
        apply All_local_env_app_inv; intuition auto.
        clear -sub a.
        induction ctx; try constructor; depelim a.
        -- rewrite subst_context_snoc.
           unfold snoc. unfold vass, snoc in H. noconf H.
           econstructor; auto.
           ++ eapply IHctx. eapply a.
           ++ simpl. destruct tu as [u tu]. exists u.
              specialize (t0 _ _ (Δ ,,, ctx) _ sub). forward t0.
              1: now rewrite app_context_assoc.
              simpl in t0.
              now rewrite subst_context_app Nat.add_0_r app_context_assoc app_length in t0.
      -- rewrite subst_context_snoc.
         unfold vdef, snoc in H |- *. noconf H.
         constructor; auto.
         ++ eapply IHctx. eapply a.
         ++ simpl.
            specialize (t1 _ _ (Δ ,,, ctx) _ sub).
            forward t1. 1: now rewrite app_context_assoc.
            simpl in t1.
            now rewrite subst_context_app Nat.add_0_r app_context_assoc app_length in t1.
         ++ simpl.
            specialize (t0 _ _ (Δ ,,, ctx) _ sub). forward t0.
            1: now rewrite app_context_assoc. simpl in t0.
            now rewrite subst_context_app Nat.add_0_r app_context_assoc app_length in t0.
      * right; exists u; intuition eauto.
    + eapply substitution_cumul; eauto.
Qed.

Corollary substitution `{cf : checker_flags} (Σ : global_env_ext) Γ Γ' s Δ (t : term) T :
  wf Σ -> subslet Σ Γ s Γ' ->
  Σ ;;; Γ ,,, Γ' ,,, Δ |- t : T ->
  Σ ;;; Γ ,,, subst_context s 0 Δ |- subst s #|Δ| t : subst s #|Δ| T.
Proof.
  intros HΣ Hs Ht.
  eapply (env_prop_typing _ _ substitution_prop); trea.
Qed.

Corollary substitution_wf_local `{cf : checker_flags} (Σ : global_env_ext) Γ Γ' s Δ :
  wf Σ -> subslet Σ Γ s Γ' ->
  wf_local Σ (Γ ,,, Γ' ,,, Δ) ->
  wf_local Σ (Γ ,,, subst_context s 0 Δ).
Proof.
  intros HΣ Hs Ht.
  eapply (env_prop_wf_local _ _ substitution_prop); trea.
Qed.

Lemma substitution0 {cf:checker_flags} (Σ : global_env_ext) Γ n u U (t : term) T :
  wf Σ ->
  Σ ;;; Γ ,, vass n U |- t : T -> Σ ;;; Γ |- u : U ->
  Σ ;;; Γ |- t {0 := u} : T {0 := u}.
Proof.
  intros HΣ Ht Hu.
  assert (wfΓ : wf_local Σ Γ).
  { apply typing_wf_local in Hu; eauto. }
  pose proof (substitution Σ Γ [vass n U] [u] [] t T HΣ) as thm.
  forward thm.
  { constructor.
    - constructor.
    - rewrite subst_empty; auto.
  }
  now apply (thm Ht).
Qed.

Lemma substitution_let {cf:checker_flags} (Σ : global_env_ext) Γ n u U (t : term) T :
  wf Σ ->
  Σ ;;; Γ ,, vdef n u U |- t : T ->
  Σ ;;; Γ |- t {0 := u} : T {0 := u}.
Proof.
  intros HΣ Ht.
  assert ((wf_local Σ Γ) * (Σ ;;; Γ |- u : U)%type) as [wfΓ tyu].
  { apply typing_wf_local in Ht; eauto with wf.
    now depelim Ht; simpl in *; unfold vdef, vass in H; noconf H.
  }
  epose proof (substitution Σ Γ [vdef n u U] _ [] t T HΣ) as thm.
  forward thm.
  { constructor.
    - constructor.
    - rewrite !subst_empty; auto.
  }
  simpl in thm.
  specialize (thm Ht). now rewrite !subst_empty in thm.
Qed.


Lemma subst_context_comm s s' Γ : 
  subst_context s 0 (subst_context s' 0 Γ) =
  subst_context (map (subst s 0) s' ++ s) 0 Γ.
Proof.
  intros.
  rewrite !subst_context_alt !mapi_compose.
  apply mapi_ext => i x.
  destruct x as [na [b|] ty] => //.
  - rewrite /subst_decl /map_decl /=; f_equal.
    + rewrite !mapi_length. f_equal. rewrite {2}Nat.add_0_r.
      rewrite subst_app_simpl.
      rewrite distr_subst_rec. rewrite Nat.add_0_r; f_equal; try lia.
      rewrite map_length. f_equal; lia.
    + rewrite mapi_length.
      rewrite subst_app_simpl.
      rewrite {2}Nat.add_0_r.
      rewrite distr_subst_rec. rewrite Nat.add_0_r; f_equal; try lia.
      rewrite map_length. f_equal; lia.
  - rewrite /subst_decl /map_decl /=; f_equal.
    rewrite !mapi_length. rewrite {2}Nat.add_0_r.
    rewrite subst_app_simpl.
    rewrite distr_subst_rec. rewrite Nat.add_0_r; f_equal; try lia.
    rewrite map_length. f_equal. lia.
Qed.

Lemma subst_app_context s s' Γ : subst_context (s ++ s') 0 Γ = subst_context s 0 (subst_context s' #|s| Γ).
Proof.
  induction Γ; simpl; auto.
  rewrite !subst_context_snoc /= /subst_decl /map_decl /=. simpl.
  rewrite IHΓ. f_equal. f_equal.
  - destruct a as [na [b|] ty]; simpl; auto.
    f_equal. rewrite subst_context_length Nat.add_0_r.
    now rewrite subst_app_simpl.
  - rewrite subst_context_length Nat.add_0_r.
    now rewrite subst_app_simpl.
Qed.

Lemma context_assumptions_subst s n Γ : 
  context_assumptions (subst_context s n Γ) = context_assumptions Γ.
Proof. apply context_assumptions_fold. Qed.
Hint Rewrite context_assumptions_subst : pcuic.


Lemma subst_app_simpl' (l l' : list term) (k : nat) (t : term) n :
  n = #|l| ->
  subst (l ++ l') k t = subst l k (subst l' (k + n) t).
Proof. intros ->; apply subst_app_simpl. Qed.


Lemma subst_app_context' (s s' : list term) (Γ : context) n :
  n = #|s| ->  
  subst_context (s ++ s') 0 Γ = subst_context s 0 (subst_context s' n Γ).
Proof.
  intros ->; apply subst_app_context.
Qed.

Lemma map_subst_app_simpl l l' k (ts : list term) : 
  map (subst l k ∘ subst l' (k + #|l|)) ts =
  map (subst (l ++ l') k) ts.
Proof.
  eapply map_ext. intros.
  now rewrite subst_app_simpl.
Qed.

Lemma simpl_map_lift x n k :
  map (lift0 n ∘ lift0 k) x = 
  map (lift k n ∘ lift0 n) x.
Proof.
  apply map_ext => t.
  rewrite simpl_lift => //; try lia.
  rewrite simpl_lift; try lia.
  now rewrite Nat.add_comm.
Qed.
