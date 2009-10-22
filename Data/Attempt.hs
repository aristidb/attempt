{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Rank2Types #-}
---------------------------------------------------------
--
-- Module        : Data.Attempt
-- Copyright     : Michael Snoyman
-- License       : BSD3
--
-- Maintainer    : Michael Snoyman <michael@snoyman.com>
-- Stability     : Unstable
-- Portability   : portable
--
-- A universal data type for computations which may fail.
---------------------------------------------------------

-- | A universal data type for computations which may fail. Errors are reported
-- using extensible exceptions. These exceptions are not explicitly stated; if
-- you want this kind of functionality, something like control-monad-exception
-- might be a more appropriate fit.
module Data.Attempt
    ( Attempt (..)
    , FromAttempt (..)
    , fa
    , attempt
    , makeHandler
    , AttemptHandler
    , module Control.Monad.Attempt.Class
    ) where

import qualified Control.Exception as E
import Control.Monad (ap)
import Control.Applicative
import Data.Generics
import Control.Monad.Attempt.Class

-- | Contains either a 'Success' value or a 'Failure' exception.
data Attempt v =
    Success v
    | forall e. E.Exception e => Failure e
    deriving (Typeable)

instance Show v => Show (Attempt v) where
    show (Success v) = "Success " ++ show v
    show (Failure e) = "Failure " ++ show e

instance Functor Attempt where
    fmap f (Success v) = Success $ f v
    fmap _ (Failure e) = Failure e
instance Applicative Attempt where
    pure = Success
    (<*>) = ap
instance Monad Attempt where
    return = Success
    (Success v) >>= f = f v
    (Failure e) >>= _ = Failure e
instance MonadAttempt Attempt where
    failure = Failure
    wrapFailure _ (Success v) = Success v
    wrapFailure f (Failure e) = Failure $ f e

-- | Any type which can be converted from an 'Attempt'. The included instances are your \"usual suspects\" for dealing with error handling. They include:
--
-- 'IO': For the IO instance, any exceptions in the 'Attempt' are thrown as
-- runtime exceptions.
--
-- 'Maybe': Returns 'Nothing' on 'Failure', or 'Just' on 'Success'.
--
-- List: Returns the empty list on 'Failure', or a singleton list on 'Success'.
--
-- 'Either' 'String': Returns 'Left' ('show' exception) on 'Failure', or 'Right' on
-- 'Success'.
--
-- 'Either' 'E.Exception': Returns 'Left' exception on 'Failure', or 'Right' on
-- 'Success'.
class FromAttempt a where
    fromAttempt :: Attempt v -> a v

-- | A shortcut for 'fromAttempt'.
fa :: FromAttempt a => Attempt v -> a v
fa = fromAttempt

instance FromAttempt IO where
    fromAttempt = attempt E.throwIO return
instance FromAttempt Maybe where
    fromAttempt = attempt (const Nothing) Just
instance FromAttempt [] where
    fromAttempt = attempt (const []) (: [])
instance FromAttempt (Either String) where
    fromAttempt = attempt (Left . show) Right
instance FromAttempt (Either E.SomeException) where
    fromAttempt = attempt (Left . E.SomeException) Right

-- | Process either the exception or value in an 'Attempt' to produce a result.
--
-- This function is modeled after 'maybe' and 'either'. The first argument must
-- accept any instances of 'E.Exception'. If you want to handle multiple types
-- of exceptions, see 'makeHandler'. The second argument converts the success
-- value.
attempt :: (forall e. E.Exception e => e -> b) -- ^ error handler
        -> (a -> b) -- ^ success handler
        -> Attempt a
        -> b
attempt _ f (Success v) = f v
attempt f _ (Failure e) = f e

-- | Convert multiple 'AttemptHandler's and a default value into an exception
-- handler.
--
-- This is a convenience function when you want to have special handling for a
-- few types of 'E.Exception's and provide another value for anything else.
makeHandler :: [AttemptHandler v] -> v -> (forall e. E.Exception e => e -> v)
makeHandler [] v _ = v
makeHandler (AttemptHandler h:hs) v e =
    case cast e of
        Nothing -> makeHandler hs v e
        Just e' -> h e'

-- | A simple wrapper value necesary due to the Haskell type system. Wraps a
-- function from a *specific* 'E.Exception' type to some value.
data AttemptHandler v = forall e. E.Exception e => AttemptHandler (e -> v)
