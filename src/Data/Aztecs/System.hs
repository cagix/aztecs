{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Data.Aztecs.System
  ( Access (..),
    runAccess,
    runAccess',
    all,
    get,
    command,
    System (..),
    runSystem,
    Cache (..),
  )
where

import Control.Monad.IO.Class
import Data.Aztecs.Command
import Data.Aztecs.Query (Query (..))
import qualified Data.Aztecs.Query as Q
import Data.Aztecs.World (Entity, World (..))
import Data.Aztecs.World.Archetypes (Archetype, ArchetypeId)
import qualified Data.Aztecs.World.Archetypes as A
import Data.Foldable (foldrM)
import Data.Kind
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Typeable
import Prelude hiding (all, read)

newtype Cache = Cache (Map Archetype ArchetypeId)
  deriving (Semigroup, Monoid)

data Access (m :: Type -> Type) a where
  PureA :: a -> Access m a
  MapA :: (a -> b) -> Access m a -> Access m b
  AppA :: Access m (a -> b) -> Access m a -> Access m b
  BindA :: Access m a -> (a -> Access m b) -> Access m b
  AllA :: Archetype -> Query a -> Access m [a]
  GetA :: Archetype -> Query a -> Entity -> Access m (Maybe a)
  CommandA :: Command m () -> Access m ()
  LiftIO :: IO a -> Access m a

instance Functor (Access m) where
  fmap = MapA

instance (Monad m) => Applicative (Access m) where
  pure = PureA
  (<*>) = AppA

instance (Monad m) => Monad (Access m) where
  (>>=) = BindA

instance (MonadIO m) => MonadIO (Access m) where
  liftIO = LiftIO

runAccess :: Access IO a -> World -> Cache -> IO (Either (Access IO a) a, World, Cache, [Command IO ()])
runAccess (PureA a) w c = return (Right a, w, c, [])
runAccess (MapA f a) w cache = do
  (a', w', cache', cmds) <- runAccess a w cache
  return
    ( case a' of
        Left a'' -> Left (MapA f a'')
        Right a'' -> Right (f a''),
      w',
      cache',
      cmds
    )
runAccess (AppA f a) w cache = do
  (f', w', cache', cmds) <- runAccess f w cache
  (a', w'', cache'', cmds') <- runAccess a w' cache'
  return
    ( case (f', a') of
        (Right f'', Right a'') -> Right (f'' a'')
        (Left f'', _) -> Left (AppA f'' a)
        (_, Left a'') -> Left (AppA f a''),
      w'',
      cache'',
      cmds ++ cmds'
    )
runAccess (BindA a f) w cache = do
  (a', w', cache', cmds) <- runAccess a w cache
  case a' of
    Left a'' -> return (Left (BindA a'' f), w', cache', cmds)
    Right a'' -> runAccess (f a'') w' cache'
runAccess (AllA a qb) w (Cache cache) = case Map.lookup (Q.buildQuery qb) cache of
  Just aId -> do
    es <- Q.all aId qb w
    return (Right es, w, Cache cache, [])
  Nothing -> return (Left (AllA a qb), w, Cache cache, [])
runAccess (GetA arch q e) w (Cache cache) = do
  case Map.lookup arch cache of
    Just aId -> do
      a <- Q.get aId q e w
      return (Right a, w, Cache cache, [])
    Nothing -> return (Left (GetA arch q e), w, Cache cache, [])
runAccess (CommandA cmd) w cache = return (Right (), w, cache, [cmd])
runAccess (LiftIO io) w cache = do
  a <- liftIO io
  return (Right a, w, cache, [])

runAccess' :: Access IO a -> World -> Cache -> IO (a, World, Cache, [Command IO ()])
runAccess' (PureA a) w c = return (a, w, c, [])
runAccess' (MapA f a) w cache = do
  (a', w', cache', cmds) <- runAccess' a w cache
  return (f a', w', cache', cmds)
runAccess' (AppA f a) w cache = do
  (f', w', cache', cmds) <- runAccess' f w cache
  (a', w'', cache'', cmds') <- runAccess' a w' cache'
  return (f' a', w'', cache'', cmds ++ cmds')
runAccess' (BindA a f) w cache = do
  (a', w', cache', cmds) <- runAccess' a w cache
  (b, w'', cache'', cmds') <- runAccess' (f a') w' cache'
  return (b, w'', cache'', cmds ++ cmds')
runAccess' (AllA _ qb) (World cs as) (Cache cache) = do
  (aId, w) <- case Map.lookup (Q.buildQuery qb) cache of
    Just q' -> return (q', World cs as)
    Nothing -> do
      (x, as') <- A.insertArchetype (Q.buildQuery qb) cs as
      return (x, World cs as')
  es <- Q.all aId qb w
  return (es, w, Cache cache, [])
runAccess' (GetA arch q e) (World cs as) (Cache cache) = do
  (aId, w) <- case Map.lookup arch cache of
    Just q' -> return (q', World cs as)
    Nothing -> do
      (x, as') <- A.insertArchetype arch cs as
      return (x, World cs as')
  a <- Q.get aId q e w
  return (a, w, Cache cache, [])
runAccess' (CommandA cmd) w cache = return ((), w, cache, [cmd])
runAccess' (LiftIO io) w cache = do
  a <- liftIO io
  return (a, w, cache, [])

-- | Query all matches.
all :: (Monad m) => Query a -> Access m [a]
all q = fst <$> all' mempty q

all' :: (Monad m) => Archetype -> Query a -> Access m ([a], Archetype)
all' arch (PureQB a) = pure ([a], arch)
all' arch (MapQB f a) = all' arch (f <$> a)
all' arch (AppQB f a) = all' arch (f <*> a)
all' arch (BindQB a f) = do
  (a', arch') <- all' arch a
  foldrM
    ( \q (acc, archAcc) -> do
        (as, archAcc') <- all' archAcc (f q)
        return (as ++ acc, archAcc')
    )
    ([], arch')
    a'
all' arch (ReadQB p arch') = do
  let arch'' = (arch <> arch')
  as <- AllA arch'' (ReadQB p arch')
  return (as, arch'')
all' arch (WriteQB p f arch') = do
  let arch'' = (arch <> arch')
  as <- AllA arch'' (WriteQB p f arch')
  return (as, arch'')
all' arch EntityQB = do
  es <- AllA arch EntityQB
  return (es, arch)

get :: (Monad m) => Entity -> Query a -> Access m (Maybe a)
get e q = fst <$> get' mempty e q

get' :: (Monad m) => Archetype -> Entity -> Query a -> Access m (Maybe a, Archetype)
get' arch _ (PureQB a) = pure (Just a, arch)
get' arch e (MapQB f qb) = get' arch e (f <$> qb)
get' arch e (AppQB f a) = get' arch e (f <*> a)
get' arch e (BindQB a f) = do
  (a', arch') <- get' arch e a
  case fmap f a' of
    Just a'' -> get' arch' e a''
    Nothing -> return (Nothing, arch')
get' arch e (ReadQB p arch') = do
  let arch'' = (arch <> arch')
  a <- GetA arch'' (ReadQB p arch') e
  return (a, arch'')
get' arch e (WriteQB p f arch') = do
  let arch'' = (arch <> arch')
  a <- GetA arch'' (WriteQB p f arch') e
  return (a, arch'')
get' arch e EntityQB = return (Just e, arch)

command :: Command m () -> Access m ()
command = CommandA

class (Typeable a) => System m a where
  access :: Access m ()

runSystem :: forall a. (System IO a) => Cache -> World -> IO (Maybe (Access IO ()), Cache, [Command IO ()], World)
runSystem cache w = do
  (result, w', cache', cmds) <- runAccess (access @IO @a) w cache
  case result of
    Left a -> return (Just a, cache', cmds, w')
    Right _ -> return (Nothing, cache', cmds, w')
