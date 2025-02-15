{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}

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

setup :: System IO () ()
setup = S.queue (A.spawn_ (Position 0 :& Velocity 1))

move :: System IO () ()
move =
  S.all
    (Q.fetch >>> Q.mapWith (\(Velocity v) (Position x) -> Position $ x + v))
    >>> S.run print

main :: IO ()
main = runSystem_ (setup >>> S.loop move)
