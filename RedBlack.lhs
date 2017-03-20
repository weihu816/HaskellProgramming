Red-Black Trees
================

This module implements a persistent version of a common balanced tree
structure: RedBlack trees.

> {-# LANGUAGE InstanceSigs, ScopedTypeVariables #-}
> module RedBlack where

RedBlack trees implement the Set interface. 

> import Persistent

If you have trouble loading the `Persistent` module, you may need to change
directories in ghci and then reload.

      Prelude> :cd ~/552/lectures
      Prelude> :r

We'll make some standard library functions available.

> import qualified Data.Maybe as Maybe
> import qualified Data.List  as List
> import Control.Monad (liftM)

And we'll use QC for testing.

> import Test.QuickCheck hiding (elements)


A red-black tree is a binary search tree where every node is
marked with a color (red or black).

> data Color = R | B deriving (Eq, Show)
> data RBT a = E | N Color (RBT a) a (RBT a)
>   deriving (Eq, Show)

> color :: RBT a -> Color
> color (N c _ _ _) = c
> color E = B

Furthermore, Red Black trees must satisfy the following 
invariants.

  1. The empty nodes at the leaves are black

  2. The root is always black

  3. From each node, every path to a leaf 
     has the same number of black nodes

  4. Red nodes have black children
  
* The first invariant is true by definition, the others we will   
have to maintain as we implement the tree.

* Together, these invariants imply that every red-black tree is
"approximately balanced", in the sense that the longest path to an
empty node is no more than twice the length of the shortest.

* From this, it follows that all operations will run in O(log_2 n)
time.

Sample Trees
------------

> good1 :: RBT Int
> good1 = N B (N B E 1 E) 2 (N B E 3 E)

Root is red

> bad1 :: RBT Int
> bad1  = N R (N B E 1 E) 2 (N B E 3 E)

In equal black height

> bad2 :: RBT Int
> bad2  = N B (N R E 1 E) 2 (N B E 3 E)

Red/Red combo

> bad3  :: RBT Int
> bad3  = N B (N R (N R E 1 E) 2 (N R E 3 E)) 4 E

Not a BST

> bad4 :: RBT Int
> bad4  = N B (N B E 1 E) 3 (N B E 2 E)

All sample trees

> trees :: [RBT Int]
> trees = [good1, bad1, bad2, bad3, bad4]


Checking the RBT invariants
---------------------------

We can write quickcheck properties for each of the invariants.

1. The empty nodes at the leaves are black. 

> prop_Rb1 :: Bool
> prop_Rb1 = color E == B

2. The root of the tree is Black.

> prop_Rb2 :: RBT Int -> Bool
> prop_Rb2 t = color t == B

3.  For all nodes in the tree, all downward paths from the
node to a leaf contain the same number of Black nodes. 

> prop_Rb3 :: RBT Int -> Bool
> prop_Rb3 (N c a x b) = prop_Rb3 a && prop_Rb3 b && bh a == bh b where
>    bh E = 1
>    bh (N c a x b) = (bh a)  + (if c == B then 1 else 0)
> prop_Rb3 E = True

4. All children of red nodes are black.

> prop_Rb4 :: RBT Int  -> Bool
> --prop_Rb4 (N c a x b) = (if c == R then color a == B && color b == B else True) && prop_Rb4 a && prop_Rb4 b
> prop_Rb4 (N R (N R _ _ _) _ _) = False
> prop_Rb4 (N R _ _ (N R _ _ _)) = False
> prop_Rb4 (N _ a _ b) = prop_Rb4 a && prop_Rb4 b
> prop_Rb4 E = True  

And satisfies the binary search tree condition.

> prop_BST :: RBT Int -> Bool
> prop_BST t = check Nothing Nothing t where
>    check :: Maybe Int -> Maybe Int -> RBT Int -> Bool  
>    check min (Just max) (N _ a x b) = min < Just x && x < max && check min (Just x) a && check (Just x) (Just max) b
>    check min Nothing    (N _ a x b) = min < Just x && check min (Just x) a && check (Just x) Nothing b     
>    check min max E           = True     


To use quickcheck, we need an arbitrary instance. We'll use one 
based on `insert` and `empty`. 

> instance (Ord a, Arbitrary a) => Arbitrary (RBT a)  where
> --   arbitrary = (arbitrary :: Gen [a]) >>= (\l -> return $ foldr insert empty l)

>    arbitrary = (foldr insert empty) <$> (arbitrary :: Gen [a])

RBT proxy for the general set properties.

> rbt :: Proxy RBT
> rbt = Proxy

> main :: IO ()
> main = do

Make sure the RBT is a set  

>   quickCheck $ prop_empty  rbt
>   quickCheck $ prop_insert rbt
>   --quickCheck $ prop_insert2 rbt

Implementation specific properties.

>   putStrLn "BST property"
>   quickCheck prop_BST
>   putStrLn "Leaves are black"
>   quickCheck prop_Rb1
>   putStrLn "Root is black"
>   quickCheck prop_Rb2
>   putStrLn "Black height the same"
>   quickCheck prop_Rb3
>   putStrLn "Red nodes have black children"
>   quickCheck prop_Rb4


Implementation
--------------

We then just need to implement the methods of the 
Set class for this data structure. 

> instance Set RBT where

>   empty :: RBT a
>   empty = E

>   member :: Ord a => a -> RBT a -> Bool
>   member x E = False
>   member x (N _ a y b)
>     | x < y     = member x a
>     | x > y     = member x b
>     | otherwise = True

>   elements :: Ord a => RBT a -> [a]
>   elements = undefined

Insertion, is, of course a bit trickier. 

>   insert :: Ord a => a -> RBT a -> RBT a
>   insert x t = blacken (ins x t)

We'll define it with the help of an auxiliary function.  This recursive
function `ins` walks down the tree until...

> ins :: Ord a => a -> RBT a -> RBT a

... it gets to an empty leaf node, in which case 
it constructs a new (red) node containing the
value being inserted...

> ins x E = N R E x E

... finds the correct subtree to insert the value, or discovers that the value
being inserted is already in the tree, in which case it returns the input
unchanged:

> ins x s@(N c a y b)
>   | x < y     = balance (N c (ins x a) y b)
>   | x > y     = balance (N c a y (ins x b))
>   | otherwise = s


Note that this definition breaks the RBT invariants in two ways --- it could
create a tree with a red root, or create a red node with a red child.

Blackening
----------

Note that `ins` creates a tree with a red root when we insert into an empty
tree.  Our first fix to insert is to blacken the top node of the tree to make
sure that invariant (2) is always satisfied.

> blacken :: RBT a -> RBT a
> blacken E = E
> blacken (N _ l v r) = N B l v r


Balancing
---------

In the recursive calls of `ins`, before returning the new tree, however, we
may need to *rebalance* to maintain the red-black invariants. The code to do
this is encapsulated in a helper function `balance`.

* The key insight in writing the balancing function is that we do not try to
rebalance as soon as we see a red node with a red child. That can be fixed
just by blackening the root of the tree, so we return this tree as-is.  (We
call such trees, which violate invariants two and four only at the root
"infrared").

The real problem comes when we've inserted a new red node between a black
parent and a red child. 

* i.e., the job of the balance function is to rebalance trees with a
black-red-red path starting at the root.

* The result of rebalancing maintains the black height by converting 
to a red parent with black children.

* Since the root has two children and four grandchildren, there are
four ways in which such a path can happen.

> balance :: RBT a -> RBT a 
> balance (N B (N R (N R a x b) y c) z d) = N R (N B a x b) y (N B c z d)
> balance (N B (N R a x (N R b y c)) z d) = N R (N B a x b) y (N B c z d)
> balance (N B a x (N R (N R b y c) z d)) = N R (N B a x b) y (N B c z d)
> -- balance (N B a x (N R b y (N R c z d))) = N R (N B a x b) y (N B c z d)
> balance t = t  

Red-Black deletion
------------------
 
We won't get to this in class, but here is an implementation of *deletion* 
from Red/Black trees (taken from [1] below).  

Deletion works by first finding the appropriate place in the tree to delete
the given element (if it exists).  At the node where we find the element, we
delete it by merging the two subtrees together.  At other nodes, when we call
delete recursively on one of the two subtrees, we may change the black height
of that subtree, so we will need to rebalance to restore the invariants.

This implementation maintains the invariant that deleting an element from a 
*black* tree of height n + 1 returns a tree of height n, while deletion from
red trees (and the empty tree) preserves the height.  Even if the element is
not in the tree we can maintain this invariant by reddening the node (and
potentially producing an infrared tree.) As above, we blacken the final result
to restore this invariant.

  
> delete :: Ord a => a -> RBT a -> RBT a
> delete x t = blacken (del t) where
> 	del E = E
> 	del (N _ a y b)
> 	    | x < y     = delLeft  a y b
> 	    | x > y     = delRight a y b
>           | otherwise = merge a b

Delete from the left subtree. If the left subtree is a black node, we need to
rebalance because its black height has changed.

>       delLeft a@(N B _ _ _) y b = balLeft (del a) y b
>       delLeft a             y b = N R (del a) y b

Rebalancing function after a left deletion from a black-rooted tree. We know
that the black height of the left subtree is one less than the black height of
the right tree. We want to return a new, balanced (though potentially
infrared) tree.

>       balLeft :: RBT a -> a -> RBT a -> RBT a
>       balLeft (N R a x b) y c            = N R (N B a x b) y c
>       balLeft bl x (N B a y b)           = balance (N B bl x (N R a y b))
>       balLeft bl x (N R (N B a y b) z c) = N R (N B bl x a) y (balance (N B b z (sub1 c)))

Helper function to reduce the black height of a tree by one by reddening the
node. Should only be called on black nodes. We know that `c` above is a black node because 
* it is the child of a red node
* `c` must have the same black height as `(N B a y b)` so it can't be `E`

>       sub1 :: RBT a -> RBT a
>       sub1 (N B a x b) = N R a x b
>       sub1 _ = error "invariance violation"

Deletion from the right subtree. Symmetric to the above code.

>       delRight a y b@(N B _ _ _) = balRight a y (del b)
>       delRight a y b             = N R a y (del b) 

>       balRight :: RBT a -> a -> RBT a -> RBT a
>       balRight a x (N R b y c)            = N R a x (N B b y c)
>       balRight (N B a x b) y bl           = balance (N B (N R a x b) y bl)
>       balRight (N R a x (N B b y c)) z bl = N R (balance (N B (sub1 a) x b)) y (N B c z bl)

Glue two red black trees together into a single tree (after deleting the
element in the middle). If one subtree is red and the other black, we can call
merge recursively, pushing the red node up. Otherwise, if both subtrees are
black or both red, we can merge the inner pair of subtrees together. If that
result is red, then we can promote it's value up. Otherwise, we may need to
rebalance.

>       merge :: RBT a -> RBT a -> RBT a
>       merge E x = x
>       merge x E = x
>       merge (N R a x b) (N R c y d) =
> 	  case merge b c of
>           N R b' z c' -> N R (N R a x b') z (N R c' y d)
> 	    bc -> N R a x (N R bc y d)
>       merge (N B a x b) (N B c y d) = 
> 	  case merge b c of
> 	    N R b' z c' -> N R  (N B a x b') z (N B c' y d)
> 	    bc -> balLeft a x (N B bc y d)
>       merge a (N R b x c)           = N R (merge a b) x c
>       merge (N R a x b) c           = N R a x (merge b c)


We can also use quickcheck to verify this definition.

> prop_delete_spec1 :: RBT Int -> Bool
> prop_delete_spec1 t = all (\x -> not (member x (delete x t))) (elements t)

> prop_delete_spec2 :: RBT Int -> Bool
> prop_delete_spec2 t = all (\(x,y) -> x == y || (member y (delete x t))) allpairs where
>   allpairs = [ (x,y) | x <- elements t, y <- elements t ]

> prop_delete_spec3 :: RBT Int -> Int -> Property
> prop_delete_spec3 t x = not (x `elem` elements t) ==> (delete x t == t)

> prop_delete_bst :: RBT Int -> Bool
> prop_delete_bst t = all (\x -> prop_BST (delete x t)) (elements t)

> prop_delete2 :: RBT Int -> Bool
> prop_delete2 t = all (\x -> prop_Rb2 (delete x t)) (elements t)

> prop_delete3 :: RBT Int -> Bool
> prop_delete3 t = all (\x -> prop_Rb3 (delete x t)) (elements t)

> prop_delete4 :: RBT Int -> Bool
> prop_delete4 t = all (\x -> prop_Rb4 (delete x t)) (elements t)

> check_delete = do
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete_spec1
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete_spec2
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete_spec3
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete2
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete3
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete4
>   quickCheckWith (stdArgs {maxSuccess=1000}) prop_delete_bst

Notes
-----

[0] See also persistant [Java
implementation](http://wiki.edinburghhacklab.com/PersistentRedBlackTreeSet)
for comparison. Requires ~350 lines for the same implementation.

[1] Stefan Kahrs, "Red-black trees with types", Journal of functional programming, 11(04), pp 425-432, July 2001

[2] Andrew Appel, ["Efficient Verified Red-Black Trees"](http://www.cs.princeton.edu/~appel/papers/redblack.pdf)
    September 2011. Presents a Coq implementation of 
    a verified Red Black Tree based on Karhs implementation.                       
  
[3] Matt Might has a blog post on an alternative version of the [RBT deletion operation](http://matt.might.net/articles/red-black-delete/).





