{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import Control.Monad.IO.Class
import Data.Aztecs
import qualified Data.Aztecs.Command as C
import qualified Data.Aztecs.Query as Q
import qualified Data.Aztecs.System as S
import qualified Data.Aztecs.Task as T

-- Components

data X = X Int deriving (Show)

instance Component X

data Y = Y Int deriving (Show)

instance Component Y

-- Systems

data A = A (Query X)

instance System IO A where
  access = A <$> query Q.read
  run (A q) = do
    liftIO $ print "A"

    T.command $ do
      e <- C.spawn (X 0)
      C.insert e (Y 1)

    xs <- T.all q
    liftIO $ print xs

data XY = XY X Y deriving (Show)

data B = B [XY]

instance System IO B where
  access =
    B
      <$> S.all (XY <$> Q.read <*> Q.read)
      <* S.alter
        (\(EntityComponent _ (X x)) -> X $ x + 1)
        (EntityComponent <$> Q.entity <*> Q.read @X)
  run (B xys) = do
    liftIO $ print "B"
    liftIO $ print xys

app :: Scheduler IO
app = schedule @Startup @_ @A [] <> schedule @Update @_ @B []

main :: IO ()
main = runScheduler app
