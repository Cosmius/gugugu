{-|
Command line entrypoint
 -}
{-# LANGUAGE ApplicativeDo     #-}
{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
module Gugugu.Lang.Scala.Command
  ( guguguScalaMain
  ) where

import           Control.Monad
import           Control.Monad.IO.Class
import           Data.ByteString        (ByteString)
import qualified Data.ByteString        as B
import           Data.FileEmbed
import           Data.Foldable
import qualified Data.Map.Strict        as Map
import qualified Data.Text              as T
import qualified Data.Text.IO           as T
import           Options.Applicative
import           System.Directory
import           System.FilePath
import           System.IO

import           Gugugu.Resolver
import           Gugugu.Utilities

import           Gugugu.Lang.Scala


-- | The command line entrypoint
guguguScalaMain :: IO ()
guguguScalaMain = runExceptIO $ do
  let version = "Gugugu Scala " <> CURRENT_PACKAGE_VERSION
  GuguguCmdOption{..} <- execParser' optParser version
  modules <- loadAllModules inputDir
  fs <- makeFiles opts modules
  liftIO $ do
    let writeRuntimeFiles pkg files = do
          let fullPkg = runtimePkg opts <> [pkg]
              pkgDir  = foldl' (\x y -> x </> T.unpack y) outputDir fullPkg
          createDirectoryIfMissing True pkgDir
          for_ files $ \(filename, content) -> do
            let path = pkgDir </> filename
            putStrLn $ "Writing file: " <> path
            withFile path WriteMode $ \h -> do
              T.hPutStr h $ "package " <> T.intercalate "." fullPkg <> "\n\n"
              B.hPut h content
    when (withCodec opts) $
      writeRuntimeFiles "codec" codecFiles
    when (withClient opts || withServer opts) $ do
      let transportFiles = transportCommonFiles
            <> (if withServer opts then insertHigherKinds serverFiles else [])
            <> (if withClient opts then insertHigherKinds clientFiles else [])
          higherKindsImport = "import scala.language.higherKinds\n\n"
          insertHigherKinds = if noHigherKindsImport opts then id else fmap $
            \(name, content) -> (name, higherKindsImport <> content)
      writeRuntimeFiles "transport" transportFiles
  for_ (Map.toList fs) $ \(p, sf) ->
    writeSrcCompToFile (outputDir </> p) sf


optParser :: Parser GuguguScalaOption
optParser = do
  packagePrefix' <- strOption $ fold
    [ long "package-prefix"
    , short 'p'
    , metavar "PACKAGE_PREFIX"
    , help "the package prefix, e.g. com.example.foo.generated"
    ]
  runtimePkg' <- strOption $ fold
    [ long "runtime-package"
    , short 'r'
    , value "gugugu.lang.scala.runtime"
    , showDefault
    , metavar "RUNTIME_PACKAGE"
    , help "location of gugugu runtime package"
    ]
  ~(withCodec, withServer, withClient) <- pWithCodecServerClient
  noHigherKindsImport <- switch $ fold
    [ long "no-higher-kinds-import"
    , help
        "pass this flag to disable import scala.language.higherKinds, which is not necessary in scala 2.13+"
    ]
  nameTransformers <- guguguNameTransformers GuguguNameTransformers
    { transModuleCode  = ToLower
    , transModuleValue = ToSnake
    , transModuleType  = NoTransform
    , transFuncCode    = NoTransform
    , transFuncValue   = ToSnake
    , transTypeCode    = NoTransform
    , transTypeFunc    = NoTransform
    , transFieldCode   = NoTransform
    , transFieldValue  = ToSnake
    , transEnumCode    = NoTransform
    , transEnumValue   = ToUpperSnake
    }
  pure GuguguScalaOption
    { packagePrefix = splitOn' "." packagePrefix'
    , runtimePkg    = splitOn' "." runtimePkg'
    , ..
    }


-- Embeded runtime files

codecFiles :: [(FilePath, ByteString)]
codecFiles = $(embedDir "runtime/codec")

transportCommonFiles :: [(FilePath, ByteString)]
transportCommonFiles = $(embedDir "runtime/transport")

serverFiles :: [(FilePath, ByteString)]
serverFiles = $(embedDir "runtime/server")

clientFiles :: [(FilePath, ByteString)]
clientFiles = $(embedDir "runtime/client")
