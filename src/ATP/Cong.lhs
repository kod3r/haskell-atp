
Congruence closure.

* Signature

> module ATP.Cong
>   ( ccsatisfiable
>   , ccvalid
>   )
> where

* Imports
                        
> import ATP.Util.Prelude 
> import qualified ATP.Equal as Equal
> import qualified ATP.Fol as Fol
> import qualified ATP.Formula as F
> import ATP.FormulaSyn
> import qualified ATP.Prop as Prop
> import qualified ATP.Skolem as Skolem
> import qualified ATP.Util.List as List
> import qualified ATP.Util.ListSet as Set
> import ATP.Util.ListSet ((∪))
> import qualified ATP.Util.UnionFind as UF
> import ATP.Util.UnionFind(Partition)
> import qualified Data.Map as Map
> import Data.Map(Map)
> import qualified Data.Maybe as Maybe

* Congruence closure

In what follows, we assume some set G of terms that is closed under
subterms, i.e. if t \in G and s is a subterm of t then s \in G. The following can
serve as the implementation and the formal definition of the set of subterms
of a term:

> subterms :: Term -> [Term]
> subterms tm = case tm of
>   (Fn _f args) -> foldr (Set.union . subterms) [tm] args
>   _ -> [tm]

Our implementation of congruence closure will take an existing congruence
relation and extend it to a new one including a given equivalence s ~ t. This
can then be iterated starting with the empty congruence to find the congruence
closure of {(s1, t1), . . . , (sn, tn)} as required. We will use a standard
union-find data structure described in appendix 2 to represent equivalences,
so closure under the equivalence properties will be automatic and we’ll just
have to pay attention to closure under congruences. So suppose we have
an existing congruence ~ and we want to extend it to a new one ~' such
that s ~' t. We need to merge the corresponding equivalence classes [s]
and [t], and may also need to merge others such as [f(s, t, f(s, s))] and
[f(t, t, f(s, t))] to maintain the congruence property. We can test whether
two terms ‘should be’ equated by a 1-step congruence by checking if all their
immediate subterms are already equivalent:

> congruent :: Partition Term -> (Term, Term) -> Bool
> congruent eqv (s,t) = case (s,t) of
>   (Fn f fargs, Fn g gargs) -> f == g && List.all2 (UF.equivalent eqv) fargs gargs
>   _ -> False

For the main algorithm, as well as the equivalence relation itself eqv, we
maintain a ‘predecessor function’ pfn mapping each canonical representative
s of an equivalence class C to the set of terms of which some s' \in C is an
immediate subterm. We can then direct our attention at the appropriate
terms each time equivalence classes are merged. It is this (eqv,pfn) pair
that is updated by the following emerge operation for a new equivalence
s ~ t.

First we normalize s --> s0 and t --> t0 based on the current equivalence
relation, and if they are already equated, we need do no more. Otherwise
we obtain the sets of predecessors, sp and tp, of the two terms. We update
the equivalence relation to eqv' to take account of the new equation, and
combine the predecessor sets to update the predecessor function to pfn'
(mapped from the new canonical representative st' in the new equivalence
relation). Then we run over all pairs from sp and tp, recursively performing
an emerge operation on terms that should become equated as a result of a
single congruence step.

> emerge :: (Term, Term) -> (Partition Term, Map Term [Term]) 
>           -> (Partition Term, Map Term [Term]) 
> emerge (s,t) (eqv, pfn) =
>   let s' = UF.canonize eqv s 
>       t' = UF.canonize eqv t in
>   if s' == t' then (eqv,pfn) else
>   let sp = Maybe.fromMaybe [] (Map.lookup s' pfn)
>       tp = Maybe.fromMaybe [] (Map.lookup t' pfn) 
>       eqv' = UF.equate (s,t) eqv 
>       st' = UF.canonize eqv' s' 
>       pfn' = Map.insert st' (sp ∪ tp) pfn 
>   in foldr (\(u,v) (eq, pf) ->
>                if congruent eq (u,v) then emerge (u,v) (eq, pf)
>                else (eq, pf))
>         (eqv', pfn') (List.allPairs (,) sp tp)

To set up the initial ‘predecessor’ function we use the following, which
updates an existing function pfn with a new mapping for each immediate
subterm s of a term t:

> predecessors :: Term -> Map Term [Term] -> Map Term [Term] 
> predecessors t pfn = case t of
>   Fn _f a -> foldr (\s m -> let tms = Maybe.fromMaybe [] (Map.lookup s m) in
>                            Map.insert s (Set.insert t tms) m)
>                    pfn (Set.setify a)
>   _ -> pfn

Hence, the following tests if a list fms of ground equations and inequations
is satisfiable. This list is partitioned into equations (pos) and inequations
(neg), which are mapped into lists of pairs of terms eqps and eqns for easier
manipulation. All the left-hand and right-hand sides are collected in
lrs, and the predecessor function pfn is constructed to handle all their subterms.
(Note that it is only pfn that determines the overall term set.) Then
congruence closure is performed starting with the trivial equivalence relation
unequal, and iteratively calling emerge over all the positive equations.
Then it is tested whether all the lefts and rights of all the negated equations
are inequivalent.

> ccsatisfiable :: [Formula] -> Bool
> ccsatisfiable fms = 
>   let (pos, neg) = List.partition F.positive fms 
>       eqps = map Equal.destEq pos
>       eqns = map (Equal.destEq . F.opp) neg
>       lrs = map fst eqps ++ map snd eqps ++ map fst eqns ++ map snd eqns
>       pfn = foldr predecessors Map.empty (Set.unions $ map subterms lrs)
>       (eqv, _) = foldr emerge (UF.unequal, pfn) eqps in
>   all (\(l, r) -> not $ UF.equivalent eqv l r) eqns

The overall decision procedure now becomes the following:

> ccvalid :: Formula -> Bool
> ccvalid fm = 
>   let fms = Prop.simpdnf $ Skolem.askolemize $ Not $ Fol.generalize fm in
>   not $ any ccsatisfiable fms

