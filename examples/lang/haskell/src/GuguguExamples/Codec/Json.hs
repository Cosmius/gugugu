{-# OPTIONS_GHC -Wall -Werror #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
module GuguguExamples.Codec.Json
  ( JsonCodecImpl(..)
  ) where

import           Control.Monad.Fail
import           Control.Monad.State               hiding (fail)
import           Data.Aeson                        (Value (..))
import qualified Data.Aeson.KeyMap                 as KM
import qualified Data.Aeson.Key                    as K
import           Data.List.NonEmpty                (NonEmpty (..), (<|))
import qualified Data.List.NonEmpty                as NonEmpty
import           Data.Scientific
import qualified Data.Text                         as T
import           Data.Time
import           Data.Traversable
import           Prelude                           hiding (fail)
import           Text.Printf

import           Gugugu.Lang.Haskell.Runtime.Codec


data JsonCodecImpl = JsonCodecImpl

type Cursor = NonEmpty Value

data P a
  = Success a
  | Failure String

dateTimeFormat :: String
dateTimeFormat = "%Y-%m-%dT%H:%M:%S"

putFocus :: Value -> StateT Cursor P ()
putFocus v = modify $ \(_ :| vs) -> v :| vs

getFocus :: StateT Cursor P Value
getFocus = gets NonEmpty.head

withPushed :: Value -> StateT Cursor P a -> StateT Cursor P a
withPushed v k = do
  modify (v <|)
  a <- k
  _ :| vs <- get
  case vs of
    []       -> fail "Bad state"
    v' : vs' -> do
      put $ v' :| vs'
      pure a


instance EncoderImpl JsonCodecImpl Value (Either String) (StateT Cursor P) where
  encodeValue c a = case execStateT (encode c a) (Null :| []) of
    Failure e         -> Left e
    Success (r :| []) -> Right r
    Success _         -> Left "unexpected finalize"

  encodeRecord _ k c a = do
    putFocus (Object KM.empty)
    k c a
  encodeRecordField _ name c a = do
    Object o <- getFocus
    encoded <- withPushed Null $ encode c a *> getFocus
    putFocus $ Object $ KM.insert (K.fromText name) encoded o

  encodeEnum _ asName c = encodeString c . asName

  encodeMaybe c a = case a of
    Nothing -> putFocus Null
    Just v  -> encode c v
  encodeList c a = do
    encoded <- for a $ \v -> withPushed Null $ encode c v *> getFocus
    putFocus $ Array encoded

  encodeUnit   _ _ = putFocus Null
  encodeBool   _ a = putFocus $ Bool a
  encodeInt32  _ a = putFocus $ Number $ fromIntegral a
  encodeDouble _ a = putFocus $ Number $ fromFloatDigits a
  encodeString _ a = putFocus $ String a

instance DecoderImpl JsonCodecImpl Value (Either String) (StateT Cursor P) where
  decodeValue c r = case runStateT (decode c) (r :| []) of
    Failure e              -> Left e
    Success (a, (_ :| [])) -> Right a
    Success _              -> Left "unexpected finalize"

  decodeRecord _ k c = do
    Object _ <- getFocus
    k c
  decodeRecordField _ name c = do
    Object o <- getFocus
    case KM.lookup (K.fromText name) o of
      Just v  -> withPushed v $ decode c
      Nothing -> fail $ printf "cannot read field: %s" name

  decodeEnum _ byName c = do
    s <- decodeString c
    case byName s of
      Just a  -> pure a
      Nothing -> fail $ printf "cannot read enum: %s" s

  decodeMaybe c = do
    j <- getFocus
    case j of
      Null -> pure Nothing
      _    -> decode c
  decodeList c = do
    Array vs <- getFocus
    for vs $ \v -> withPushed v $ decode c

  decodeUnit   _ = do
    Null <- getFocus
    pure ()
  decodeBool   _ = do
    Bool a <- getFocus
    pure a
  decodeInt32  _ = do
    Number v <- getFocus
    case floatingOrInteger v of
      Right a -> pure a
      Left f  -> fail $ printf "cannot read Int32: %f" (f :: Double)
  decodeDouble _ = do
    Number v <- getFocus
    pure $ toRealFloat v
  decodeString _ = do
    String a <- getFocus
    pure a


instance ForeignEncodersImpl JsonCodecImpl (StateT Cursor P) where
  encodeDateTime c =
    encodeString c . T.pack . formatTime defaultTimeLocale dateTimeFormat

instance ForeignDecodersImpl JsonCodecImpl (StateT Cursor P) where
  decodeDateTime c = do
    s <- decodeString c
    -- parseTimeM in time-1.8.0.2 uses Monad.fail instead of MonadFail.fail
    case parseTimeM False defaultTimeLocale dateTimeFormat (T.unpack s) of
      Just v  -> pure v
      Nothing -> fail "cannot read LocalDateTime"


instance Functor P where
  fmap f p = case p of
    Success a -> Success (f a)
    Failure e -> Failure e

instance Applicative P where
  pure = Success
  pf <*> pa = case pf of
    Success f -> fmap f pa
    Failure e -> Failure e

instance Monad P where
  p >>= k = case p of
    Success a -> k a
    Failure e -> Failure e

instance MonadFail P where
  fail = Failure
