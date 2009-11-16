
* Signature

> module ATP.Stal 
>   ( stalmarck )
> where

* Imports

#include "undefined.h" 

> import ATP.Util.Prelude 
> import qualified ATP.DefCnf as Cnf
> import qualified ATP.Formula as F
> import ATP.FormulaSyn
> import qualified ATP.Prop as Prop
--> import qualified ATP.PropExamples as E
> import qualified ATP.Util.List as List
> import qualified ATP.Util.ListSet as Set
> import ATP.Util.ListSet ((∪), (∩), (\\))
> import qualified ATP.Util.Log as Log
> import ATP.Util.Log (Log)
> import qualified ATP.Util.UnionFind as UF
> import ATP.Util.UnionFind (Partition)
> import qualified Data.Map as Map
> import Data.Map (Map)

* Util

> type Part = Partition Formula
> type Pair = (Formula, Formula)
> type Pairs = [Pair]
> type Trigger = (Pair, Pairs)
> type Triggers = [Trigger]
> type TrigMap = Map Formula Triggers
> type Erf = (Part, TrigMap)

* Stålmark's method

We'll present Stålmarck's method in its original setting, although
the basic dilemma rule can also be incorporated into the same
clausal framework as DPLL, as considered in exercise 15 below. The
formula to be tested for satisfiability is first reduced to a
conjunction of `triplets' li , lj lk with the literals li
representing subformulas of the original formula. We derive this as
in the 3-CNF procedure from section 2.8, introducing
abbreviations for all nontrivial subformulas but omitting the final
CNF transformation of the triplets:

> name :: Rel -> String
> name (R f []) = f
> name _ = __IMPOSSIBLE__ 

> triplicate :: Formula -> (Formula, [Formula])
> triplicate fm = 
>   let fm' = Prop.nenf fm
>       n = 1 + F.overatoms (Cnf.maxVarIndex "p_" . name) fm' 0 
>       (p, defs, _) = Cnf.maincnf (fm', Map.empty, n)
>   in (p, map (snd . snd) (Map.toList defs))

Rather than deriving clauses, the rules in Stålmarck's method derive equivalences
p , q where p and q are either literals or the formulas > or ?.y The
underlying `simple rules' in Stålmarck's method enumerate the new equivalences
that can be deduced from a triplet given some existing equivalences.
For example, if we assume a triplet p , q ^ r then:

○ If we know r ⇔ ⊤ we can deduce p ⇔ q.
○ If we know p ⇔ ⊤ we can deduce q ⇔ ⊤ and r ⇔ ⊤.
○ If we know q ⇔ ⊥ we can deduce p ⇔ ⊥.
○ If we know q ⇔ r we can deduce p ⇔ q and p ⇔ r.
○ If we know p ⇔ ¬ q we can deduce p ⇔ ⊥, q ⇔ ⊤ and r ⇔ ⊥.

We'll try to avoid deducing redundant sets of equivalences. To identify
equivalences that are essentially the same (e.g. p ⇔ ¬ q, ¬ q ⇔ p and q ⇔ ¬ p)
we force alignment of each p, q such that the atom on the right is no bigger
than the one on the left, and the one on the left is never negated:

> atom :: Formula -> Formula
> atom lit = if F.negative lit then F.opp lit else lit

> align :: Pair -> Pair
> align (p, q) = 
>   if atom p < atom q then align (q, p) else
>   if F.negative p then (F.opp p, F.opp q) else (p, q)

Our representation of equivalence classes rests on the union-find data
structure from Appendix 2. The equate function described there merges
two equivalence classes, but we will ensure that whenever p and q are to be
identified, we also identify -p and -q:

> equate2 :: Pair -> Part -> Part
> equate2 (p, q) eqv =  UF.equate (F.opp p, F.opp q) (UF.equate (p, q) eqv)

We'll also ignore redundant equivalences, i.e. those that already follow
from the existing equivalence, including the immediately trivial p ⇔ p:

> irredundant :: Part -> Pairs -> Pairs
> irredundant rel eqs = case eqs of
>   [] -> []
>   (p, q) : oth -> 
>     if UF.canonize rel p == UF.canonize rel q then irredundant rel oth
>     else Set.insert (p, q) $ irredundant (equate2 (p, q) rel) oth

It would be tedious and error-prone to enumerate by hand all the ways in
which equivalences follow from each other in the presence of a triplet, so we
will deduce this information automatically. The following takes an assumed
equivalence peq and triplet fm, together with a list of putative equivalences
eqs. It returns an irredundant set of those equivalences from eqs that follow
from peq and fm together:

> consequences :: Pair -> Formula -> Pairs -> Pairs
> consequences peq@(p, q) fm eqs =
>   let follows (r, s) = Prop.tautology $ ((p ⇔ q) ∧ fm) ⊃ (r ⇔ s) in
>   irredundant (equate2 peq UF.unequal) (filter follows eqs)

To generate the entire list of `triggers' generated by a triplet, i.e. a list of
equivalences with their consequences, we just need to apply this function to
each canonical equivalence:

> triggers :: Formula -> Triggers
> triggers fm = 
>   let poslits = Set.insert (⊤) (map Atom $ Prop.atoms fm)
>       lits = poslits ∪ map F.opp poslits
>       pairs = List.allPairs (,) lits lits
>       npairs = filter (\(p, q) -> atom p /= atom q) pairs
>       eqs = Set.setify $ map align npairs
>       raw = map (\p -> (p, consequences p fm eqs)) eqs
>   in filter (not . null . snd) raw

pp $ triggers [$form| p <=> (q /\ r) |]

We could apply this to the actual triplets in the formula (indeed, it is
applicable to any formula fm), but it's more efficient to precompute it for
the possible forms p ⇔ q ∧ r, p ⇔ q ∨ r, p ⇔ q ⊃ r and p ⇔ (q ⇔ r),
then instantiate the results for each instance in question. However after
instantiation, we may need to realign, and also eliminate double negations
if some of p, q and r are replaced by negative literals.

> trigger :: Formula -> Triggers
> trigger fm = case fm of
>   [$form| $x ⇔ $y ∧ $z |] -> instTrigger (x, y, z) trigAnd
>   [$form| $x ⇔ $y ∨ $z |] -> instTrigger (x, y, z) trigOr
>   [$form| $x ⇔ $y ⊃ $z |] -> instTrigger (x, y, z) trigImp
>   [$form| $x ⇔ ($y ⇔ $z) |] -> instTrigger (x, y, z) trigIff
>   _ -> __IMPOSSIBLE__ 
>  where 
>   trigAnd = triggers [$form| p ⇔ q ∧ r |]
>   trigOr = triggers [$form| p ⇔ q ∨ r |]
>   trigImp = triggers [$form| p ⇔ q ⊃ r |]
>   trigIff = triggers [$form| p ⇔ (q ⇔ r) |]
>   ddnegate [$form| ¬ ¬ $p |] = p
>   ddnegate f = f
>   instfn (x, y, z) = 
>     let subfn = Map.fromList [ (R "p" [], x), (R "q" [], y), (R "r" [], z) ] 
>     in ddnegate . Prop.apply subfn
>   inst2fn i (p, q) = align $ (instfn i p, instfn i q)
>   instnfn i (a, c) = (inst2fn i a, map (inst2fn i) c)
>   instTrigger = map . instnfn

The core of Stålmarck's method is zero-saturation, i.e. the exhaustive application
of the simple rules to derive new equivalences from existing ones.
Given an equivalence, only triggers sharing some atoms with it could yield
new information from it, so we set up a function mapping literals to relevant
triggers:

> relevance :: Triggers -> TrigMap
> relevance trigs =
>   let insertRelevant :: Formula -> Trigger -> TrigMap -> TrigMap
>       insertRelevant p trg f = 
>         Map.insert p (Set.insert trg $ maybe [] id (Map.lookup p f)) f
>       insertRelevant2 trg@((p,q), _) = insertRelevant p trg . insertRelevant q trg
>   in foldr insertRelevant2 Map.empty trigs 

The principal zero-saturation function, equatecons, defined below, derives
new information from an equation p0 = q0, and in general modifies
both the equivalence relation eqv between literals and the `relevance' function
rfn.

We maintain the invariant that the relevance function maps a literal l that
is a canonical equivalence class representative to the set of triggers where the
triggering equation contains some l0 equivalent to l under the equivalence
relation. Initially, there are no non-trivial equations, so this collapses to the
special case l0 = l, corresponding to the action of the relevance function.
First of all, we get canonical representatives p and q for the two literals.
If these are already the same then the equation p0 = q0 yields no new in
formation and we return the original equivalence and relevance. Otherwise,
we similarly canonize the negations of p0 and q0 to get p' and q', which
we also need to identify.

The equivalence relation is updated just by using equate2, but updating
the relevance function is a bit more complicated. We get the set of triggers
where the triggering equation involves something (originally) equivalent to
p (sp pos) and p' (sp neg), and similarly for q and q'. Now, the new
equations we have effictively introduced by identifying p and q are all those
with something equivalent to p on one side and something equivalent to q
on the other side, or equivalent to p' and q'. These are collected as the set
news.

As for the new relevance function, we just collect the triggers componentwise
from the two equivalence classes. This has to be indexed by the
canonical representatives of the merged equivalence classes corresponding
to p and p', and we have to re-canonize these as we can't a priori predict
which of the two representatives that were formerly canonical will actually
get chosen.

> equatecons :: Pair -> Erf -> (Pairs, Erf)
> equatecons (p0, q0) erf@(eqv, rfn) =
>   let p = UF.canonize eqv p0 
>       q = UF.canonize eqv q0
>   in if p == q then ([], erf) else
>   let p' = UF.canonize eqv (F.opp p0)
>       q' = UF.canonize eqv (F.opp q0)
>       eqv' = equate2 (p, q) eqv
>       look f = maybe [] id (Map.lookup f rfn)
>       spPos = look p
>       spNeg = look p'
>       sqPos = look q
>       sqNeg = look q'
>       rfn' = Map.insert (UF.canonize eqv' p) (spPos ∪ sqPos) $
>               Map.insert (UF.canonize eqv' p') (spNeg ∪ sqNeg) rfn
>       nw = (spPos ∩ sqPos) ∪ (spNeg ∩ sqNeg)
>   in (foldr (Set.union . snd) [] nw, (eqv', rfn'))

Though this function was a bit involved, it's now easy to perform zerosaturation,
taking an existing equivalence-relevance pair and updating it
with new equations assigs and all the consequences:

> zeroSaturate :: Erf -> Pairs -> Erf
> zeroSaturate erf assigs = case assigs of
>   [] -> erf
>   (p, q) : ts -> 
>    let (news, erf') = equatecons (p, q) erf in
>    zeroSaturate erf' (ts ∪ news)             

At some point, we would like to check whether a contradiction has been
reached, i.e. some literal has become identified with its negation. The
following function performs zero-saturation, then if a contradiction has been
reached equates `true' and `false':

> zeroSaturateAndCheck :: Erf -> Pairs -> Erf
> zeroSaturateAndCheck erf trigs =
>   let erf'@(eqv', _) = zeroSaturate erf trigs
>       vars = filter F.positive (UF.equated eqv')
>   in if List.any (\x -> UF.canonize eqv' x == UF.canonize eqv' ((¬) x)) vars
>      then snd $ equatecons (Top, Not Top) erf' else erf'

to allow a simple test later on when needed:

> truefalse :: Part -> Bool
> truefalse pfn = UF.canonize pfn (Not Top) == UF.canonize pfn Top

* Higher Saturation Levels

To implement higher levels of saturation, we need to be able to take the
intersection of equivalence classes derived in two branches. We start with
an auxiliary function to equate a whole set of elements:

> equateset :: [Formula] -> Erf -> Erf
> equateset s0 eqfn = case s0 of
>   a : s1@(b : _) -> equateset s1 (snd $ equatecons (a, b) eqfn)
>   _ -> eqfn

Now to intersect two equivalence classes eqv1 and eqv2, we repeatedly
pick some literal x, find its equivalence classes s1 and s2 w.r.t. each equivalence
relation, intersect them to give s, and then identify that set of literals
in the `output' equivalence relation using equateset. Here rev1 and rev2
are reverse mappings from a canonical representative back to the equivalence
class, and erf is an equivalence relation to be augmented with the
new equalities resulting.

> inter :: [Formula] -> Erf -> Erf -> Map Formula [Formula] -> Map Formula [Formula] -> Erf -> Erf
> inter els erf1@(eq1, _) erf2@(eq2, _) rev1 rev2 erf = case els of
>   [] -> erf
>   x:xs -> 
>     let b1 = UF.canonize eq1 x
>         b2 = UF.canonize eq2 x
>         s1 = maybe __IMPOSSIBLE__ id (Map.lookup b1 rev1)
>         s2 = maybe __IMPOSSIBLE__ id (Map.lookup b2 rev2)
>         s = s1 ∩ s2
>     in inter (xs \\ s) erf1 erf2 rev1 rev2 (equateset s erf)

We can obtain reversed equivalence class mappings thus:

> reverseq :: [Formula] -> Part -> Map Formula [Formula]
> reverseq domain eqv =
>   let a1 = map (\x -> (x, UF.canonize eqv x)) domain in
>   foldr (\(y, x) f -> Map.insert x (Set.insert y (maybe [] id $ Map.lookup x f)) f)
>     Map.empty a1

The overall intersection function can exploit the fact that if contradiction
is detected in one branch, the other branch can be taken over in its entirety.

> stalIntersect :: Erf -> Erf -> Erf -> Erf
> stalIntersect erf1@(eq1, _) erf2@(eq2, _) erf =
>   if truefalse eq1 then erf2 else if truefalse eq2 then erf1 else
>   let dom1 = UF.equated eq1
>       dom2 = UF.equated eq2
>       comdom = dom1 ∩ dom2
>       rev1 = reverseq dom1 eq1 
>       rev2 = reverseq dom2 eq2
>   in inter comdom erf1 erf2 rev1 rev2 erf

In n-saturation, we run through the variables, case-splitting over each in
turn, (n - 1)-saturating the subequivalences and intersecting them. This
is repeated until a contradiction is reached, when we can terminate, or no
more information is derived, in which case the formula is not n-easy and a
higher saturation level must be tried. The implementation uses two mutually
recursive function: saturate takes new assignments, zero-saturates to
derive new information from them, and repeatedly calls splits:

> saturate :: Int -> Erf -> Pairs -> [Formula] -> Erf
> saturate n erf assigs allvars =
>   let erf'@(eqv', _) = zeroSaturateAndCheck erf assigs in
>   if n == 0 || truefalse eqv' then erf' else
>   let erf''@(eqv'', _) = splits n erf' allvars allvars in
>   if eqv'' == eqv' then erf'' else saturate n erf'' [] allvars

which in turn runs splits over each variable in turn, performing (n - 1)-
saturations and intersecting the results:

> splits :: Int -> Erf -> [Formula] -> [Formula] -> Erf
> splits n erf@(eqv, _) allvars vars = case vars of
>   [] -> erf
>   p : ovars -> 
>     if UF.canonize eqv p /= p then splits n erf allvars ovars else
>     let erf0 = saturate (n-1) erf [(p, Not Top)] allvars
>         erf1 = saturate (n-1) erf [(p, Top)] allvars
>         erf'@(eqv', _) = stalIntersect erf0 erf1 erf
>     in if truefalse eqv' then erf' else splits n erf' allvars ovars

* Top-level function

We are now ready to implement a tautology prover based on Stålmarck's
method. The main loop saturates up to a limit, with progress indications:

> saturateUpto :: Log m => [Formula] -> Int -> Int -> Triggers -> Pairs -> m Bool
> saturateUpto vars n m trigs assigs =
>  if n > m then error $ "Not " ++ show m ++ "-easy" else do
>  Log.infoM "saturateUpto" $ "*** Starting " ++ show n ++ "-saturation"
>  Log.debugM' "saturateUpto" $ pPrint (vars, n, m, trigs, assigs)
>  let (eqv, _) = saturate n (UF.unequal, relevance trigs) assigs vars
>  if truefalse eqv then return True else saturateUpto vars (n+1) m trigs assigs

The top-level function transforms the negated input formula into triplets,
sets the entire formula equal to True and saturates. The triggers are collected
together initially in a triggering function, which is then converted to
a set:

> stalmarck :: Log m => Formula -> m Bool
> stalmarck fm = 
>   let includeTrig (e, cqs) f = Map.insert e (cqs ∪ maybe [] id (Map.lookup e f)) f
>       fm' = Prop.simplify $ (¬) fm
>   in if fm' == (⊥) then return True else if fm' == (⊤) then return False else
>   let (p, triplets) = triplicate fm'
>       trigfn = foldr (flip (foldr includeTrig) . trigger) Map.empty triplets
>       vars = map Atom (Set.unions $ map Prop.atoms triplets)
>   in saturateUpto vars 0 2 (Map.toList trigfn) [(p, (⊤))]

