{-# LANGUAGE Arrows #-}

module Main where

import Control.Arrow ((>>>))
import Data.Aztecs
import qualified Data.Aztecs.Access as A
import qualified Data.Aztecs.Query as Q
import qualified Data.Aztecs.System as S

newtype Position = Position Int deriving (Show)

instance Component Position

newtype Velocity = Velocity Int deriving (Show)

instance Component Velocity

setup :: System () ()
setup = S.queue . const . A.spawn_ $ bundle (Position 0) <> bundle (Velocity 1)

move :: System () ()
move =
  S.map
    ( proc () -> do
        Velocity v <- Q.fetch -< ()
        Position p <- Q.fetch -< ()
        Q.set -< Position $ p + v
    )
    >>> S.task print

app :: Schedule IO () ()
app = schedule setup >>> forever (schedule move)

main :: IO ()
main = runSchedule_ $ app
