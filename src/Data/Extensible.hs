{-# LANGUAGE DataKinds, TypeOperators, PolyKinds, KindSignatures, GADTs, MultiParamTypeClasses, TypeFamilies, FlexibleInstances, FlexibleContexts, UndecidableInstances, ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ViewPatterns, BangPatterns #-}
module Data.Extensible (
  -- * Lookup
  Position
  , (∈)(..)
  -- * Product
  , (:*)(..)
  , (<:*)
  , unconsP
  , hoistP
  , outP
  , record
  , recordAt
  -- * Sum
  , (:|)(..)
  , (<:|)
  , exhaust
  , inS
  -- * Utilities
  , K0(..)
  , platter
  , (<%)
  , K1(..)
  , Union(..)
  , liftU
  , Match(..)
  , match
  , mapMatch
  , (<?%)
  , (<?!)
  ) where
import Unsafe.Coerce
import Data.Bits
import Data.Typeable
import Control.Applicative

-- | The extensible product type
data (h :: k -> *) :* (s :: [k]) where
  Nil :: h :* '[]
  Tree :: h x
    -> h :* Half xs
    -> h :* Half (Tail xs)
    -> h :* (x ': xs)

instance Show (h :* '[]) where
  show Nil = "Nil"

instance (Show (h :* xs), Show (h x)) => Show (h :* (x ': xs)) where
  showsPrec d (unconsP -> (x, xs)) = showParen (d > 10) $
     showsPrec 6 x
    . showString " <:* "
    . showsPrec 6 xs

unconsP :: h :* (x ': xs) -> (h x, h :* xs)
unconsP (Tree a Nil _) = (a, unsafeCoerce Nil)
unconsP (Tree a bd c) = (a, let (b, d) = unconsP (unsafeCoerce bd) in unsafeCoerce $ Tree b (unsafeCoerce c) d)

-- | /O(log n)/ Add an element to a product.
(<:*) :: h x -> h :* xs -> h :* (x ': xs)
a <:* Tree b c d = Tree a (unsafeCoerce (<:*) b d) c --  (Half (x1 : xs1) ~ (x1 : Half (Tail xs1)))
a <:* Nil = Tree a Nil Nil
infixr 5 <:*

hoistP :: (forall x. g x -> h x) -> g :* xs -> h :* xs
hoistP t (Tree h a b) = Tree (t h) (hoistP t a) (hoistP t b)
hoistP _ Nil = Nil

-- | /O(log n)/ Pick a specific element.
outP :: forall h x xs. (x ∈ xs) => h :* xs -> h x
outP = view $ recordAt (position :: Position x xs)
{-# INLINE outP #-}

-- | /O(log n)/ A lens for a specific element.
record :: forall h x xs f. (Functor f, x ∈ xs) => (h x -> f (h x)) -> h :* xs -> f (h :* xs)
record = recordAt (position :: Position x xs)
{-# INLINE record #-}

view :: ((a -> Const a a) -> (s -> Const a s)) -> s -> a
view l = unsafeCoerce (l Const)
{-# INLINE view #-}

recordAt :: forall h x xs f. (Functor f) => Position x xs -> (h x -> f (h x)) -> h :* xs -> f (h :* xs)
recordAt (Position x) f = go x where
  go 0 (Tree h a b) = fmap (\h' -> Tree h' a b) $ unsafeCoerce f h
  go n (Tree h a b) = let m = n - 1 in case m .&. 1 of
    0 -> fmap (\a' -> Tree h a' b) $ unsafeCoerce go (shiftR m 1) a
    _ -> fmap (\b' -> Tree h a b') $ unsafeCoerce go (shiftR m 1) b
  go _ Nil = error "Impossible"
{-# INLINE recordAt #-}

-- | /O(log n)/
inS :: (x ∈ xs) => h x -> h :| xs
inS = UnionAt position
{-# INLINE inS #-}

-- | /O(n)/ Naive pattern match
(<:|) :: (h x -> r) -> (h :| xs -> r) -> h :| (x ': xs) -> r
(<:|) r _ (UnionAt (Position 0) h) = r (unsafeCoerce h)
(<:|) _ c (UnionAt (Position n) h) = c $ unsafeCoerce $ UnionAt (Position (n - 1)) h

exhaust :: h :| '[] -> r
exhaust _ = error "Impossible"

-- | The extensible sum type
data (h :: k -> *) :| (s :: [k]) where
  UnionAt :: Position x xs -> h x -> h :| xs

instance Show (h :| '[]) where
  show _ = undefined

instance (Show (h x), Show (h :| xs)) => Show (h :| (x ': xs)) where
  showsPrec d = (\h -> showParen (d > 10) $ showString "inS " . showsPrec d h)
    <:| showsPrec d

newtype K0 a = K0 { getK0 :: a } deriving (Eq, Ord, Read, Typeable)

-- | /O(log n)/ Add a plain value to a product.
(<%) :: x -> K0 :* xs -> K0 :* (x ': xs)
(<%) = unsafeCoerce (<:*)
{-# INLINE (<%) #-}
infixr 5 <%

instance Show a => Show (K0 a) where
  showsPrec d (K0 a) = showParen (d > 10) $ showString "K0 " . showsPrec 11 a

-- | /O(log n)/ A lens for a plain value in a product.
platter :: forall f x xs. (x ∈ xs, Functor f) => (x -> f x) -> (K0 :* xs -> f (K0 :* xs))
platter = unsafeCoerce (record :: (K0 x -> f (K0 x)) -> (K0 :* xs -> f (K0 :* xs)))
{-# INLINE platter #-}

newtype K1 a f = K1 { getK1 :: f a } deriving (Eq, Ord, Read, Typeable)

instance Show (f a) => Show (K1 a f) where
  showsPrec d (K1 a) = showParen (d > 10) $ showString "K1 " . showsPrec 11 a

newtype Match h a x = Match { runMatch :: h x -> a }

mapMatch :: (a -> b) -> Match h a x -> Match h b x
mapMatch f (Match g) = Match (f . g)
{-# INLINE mapMatch #-}

-- | /O(log n)/ Perform pattern match.
match :: Match h a :* xs -> h :| xs -> a
match p (UnionAt pos h) = runMatch (view (recordAt pos) p) h
{-# INLINE match #-}

(<?%) :: (x -> a) -> Match K0 a :* xs -> Match K0 a :* (x ': xs)
(<?%) = unsafeCoerce (<:*)
infixr 1 <?%

(<?!) :: (f x -> a) -> Match (K1 x) a :* xs -> Match (K1 x) a :* (f ': fs)
(<?!) = unsafeCoerce (<:*)
infixr 1 <?!

newtype Union fs a = Union { getUnion :: K1 a :| fs }

liftU :: (f ∈ fs) => f a -> Union fs a
liftU = Union . inS . K1
{-# INLINE liftU #-}

deriving instance Show (K1 a :| fs) => Show (Union fs a)

---------------------------------------------------------------------

newtype Position x xs = Position Int deriving Show

class (x :: k) ∈ (xs :: [k]) where
  position :: Position x xs

instance Record (Lookup x xs) => x ∈ xs where
  position = Position $ theInt (Proxy :: Proxy (Lookup x xs))
  {-# INLINE position #-}

type family Half (xs :: [k]) :: [k] where
  Half '[] = '[]
  Half (x ': y ': zs) = x ': zs
  Half (x ': '[]) = x ': '[]

type family Tail (xs :: [k]) :: [k] where
  Tail (x ': xs) = xs
  Tail '[] = '[]

data Nat = Zero | DNat Nat | SDNat Nat | NotFound

retagD :: (Proxy n -> a) -> proxy (DNat n) -> a
retagD f _ = f Proxy
{-# INLINE retagD #-}

retagSD :: (Proxy n -> a) -> proxy (SDNat n) -> a
retagSD f _ = f Proxy
{-# INLINE retagSD #-}

class Record n where
  theInt :: Proxy n -> Int

instance Record Zero where
  theInt _ = 0
  {-# INLINE theInt #-}

instance Record n => Record (DNat n) where
  theInt = (\n -> n + n) <$> retagD theInt
  {-# INLINE theInt #-}

instance Record n => Record (SDNat n) where
  theInt = (\n -> n + n + 1) <$> retagSD theInt
  {-# INLINE theInt #-}

type family Lookup (x :: k) (xs :: [k]) :: Nat where
  Lookup x (x ': xs) = Zero
  Lookup x (y ': ys) = Succ (Lookup x ys)
  Lookup x '[] = NotFound

type family Succ (x :: Nat) :: Nat where
  Succ Zero = SDNat Zero
  Succ (DNat n) = SDNat n
  Succ (SDNat n) = DNat (Succ n)
  Succ NotFound = NotFound
