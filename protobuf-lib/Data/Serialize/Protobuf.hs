-- | Define utils for serializtion of protobuf message
module Data.Serialize.Protobuf ( 
    -- * Wiretag
    WireTag(..)
  , getWireTag
  , skipUnknownField
  , getPacked
  , getPbString
  , getPbEnum
  , getPbBytestring
  , getDelimMessage
  ) where

import Control.Applicative
import Control.Monad
import Data.Bits
import Data.ByteString          (ByteString)
import Data.Serialize
import Data.Serialize.Get
import Data.Serialize.Put
import Data.Serialize.VarInt
import qualified Data.Sequence as Seq
import           Data.Sequence   (Seq,(|>))
import Debug.Trace

import Data.Protobuf.Classes


getVarInt :: Get Int
getVarInt = fromIntegral <$> getVarInt64

data WireTag = WireTag {-# UNPACK #-} !Int {-# UNPACK #-} !Int
               deriving Show


getWireTag :: Get WireTag
getWireTag = do
  i <- getVarInt
  return $! WireTag (i `shiftR` 3) (0x07 .&. i)

getSequence :: Get a -> Get [a]
getSequence getter = do
  n <- getVarInt
  replicateM n getter

skipUnknownField :: WireTag -> Get ()
skipUnknownField (WireTag _ t) =
  case t of
    0 -> void getVarInt
    1 -> skip 8
    2 -> skip =<< getVarInt
    3 -> fail "Groups are not supported"
    4 -> fail "Groups are not supported"
    5 -> skip 4 
    _ -> fail ("Bad wire tag: " ++ show t)

getPacked :: Get a -> Get (Seq a)
getPacked getter = do
  n <- getVarInt
  isolate n $ getSeq Seq.empty getter
  
getSeq :: Seq a -> Get a -> Get (Seq a)
getSeq s getter = do 
  f <- isEmpty 
  if f 
    then return s
    else do x <- getter
            getSeq (s |> x) getter



getPbString :: Get String
getPbString = do
  n <- getVarInt
  isolate n $ repeatedly

repeatedly :: Get String
repeatedly = do
  f <- isEmpty
  if f
    then return []
    else (:) <$> get <*> repeatedly

getPbEnum :: PbEnum a => Get a
getPbEnum = toPbEnum <$> getVarInt

getPbBytestring :: Get ByteString
getPbBytestring = getByteString =<< getVarInt

getDelimMessage :: Message m => Get (m Required)
getDelimMessage = do
  n <- getVarInt
  isolate n $ getMessage