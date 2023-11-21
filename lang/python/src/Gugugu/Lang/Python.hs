{-|
Python target
 -}
{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE StrictData        #-}
{-# LANGUAGE TupleSections     #-}
module Gugugu.Lang.Python
  ( GuguguPythonOption(..)
  , makeFiles
  ) where

import           Control.Applicative
import           Control.Monad.Except
import           Control.Monad.Reader
import           Data.Bifunctor
import           Data.Foldable
import qualified Data.List                      as List
import           Data.List.NonEmpty             (NonEmpty (..))
import qualified Data.List.NonEmpty             as NonEmpty
import           Data.Map.Strict                (Map)
import qualified Data.Map.Strict                as Map
import           Data.Maybe
import           Data.Set                       (Set)
import qualified Data.Set                       as Set
import           Data.Text                      (Text)
import qualified Data.Text                      as T
import           Data.Traversable
import           Data.Tuple
import           System.FilePath
import           Text.Printf

import           Gugugu.Resolver
import           Gugugu.Utilities

import           Gugugu.Lang.Python.SourceUtils


-- | Option for 'makeFiles'
data GuguguPythonOption
  = GuguguPythonOption
    { packagePrefix    :: [Text]                  -- ^ Package prefix
    , runtimePkg       :: [Text]                  -- ^ Runtime module
    , withCodec        :: Bool                    -- ^ True if generate codec
    , withServer       :: Bool                    -- ^ True if generate server
    , withClient       :: Bool                    -- ^ True if generate client
    , nameTransformers :: GuguguNameTransformers  -- ^ Name transformers
    }
  deriving Show

-- | Make Python AST from 'Module's
makeFiles :: MonadError String m
          => GuguguPythonOption
          -> [Module]
          -> m (Map FilePath FileInput)
makeFiles = makeModules


type GuguguK r m = ( MonadError String m
                   , MonadReader r m
                   , HasGuguguPythonOption r
                   , HasResolutionContext r
                   )

data GuguguPythonEnv
  = GuguguPythonEnv
    { gOpts :: GuguguPythonOption
    , gCtx  :: ResolutionContext
    }
  deriving Show

class HasGuguguPythonOption a where
  toGuguguPythonOption :: a -> GuguguPythonOption

type ForeignTypeResult = (Set ImportStmt, ([Statement], [Statement]))
type ImportsAndForeign = (Set ImportStmt, ForeignTypeResult)

makeModules :: MonadError String m
            => GuguguPythonOption
            -> [Module]
            -> m (Map FilePath FileInput)
makeModules opts@GuguguPythonOption{..} modules = do
  let moduleMap = Map.fromList $
        fmap (\md@Module{..} -> (moduleName, md)) modules
  foreignsAndFiles <- for modules $ \md -> do
    let rCtx = ResolutionContext
          { rcModules       = moduleMap
          , rcCurrentModule = md
          }
        env  = GuguguPythonEnv
          { gOpts = opts
          , gCtx  = rCtx
          }
    runReaderT (makeModule md) env
  let (foreigns, files) = unzip foreignsAndFiles
  let (iForeign, (encodeImpls, decodeImpls)) = fold foreigns
  let (iTyping, mTyping) = importModule $ "typing" :| []
      (iAbc, eAbc)       = importItem $ "abc" :| ["ABC"]
  let allFiles      = Map.fromList $
           [(pkgPath, pkgModule)]
        <> [(foreignPath, foreignModule) | withCodec]
        <> files
      foreignModule = FileInput
        { fiImports = importAnn : Set.toAscList (iForeign <> iTyping <> iAbc)
        , fiContent =
            [ SA AssignmentStmt
                { asTarget = TSimple "S"
                , asValue  = mTyping `EAttr` "TypeVar"
                    `eCall` [ESimple $ unsafeQuote "S"]
                }
            , f "ForeignEncodersImpl" encodeImpls
            , f "ForeignDecodersImpl" decodeImpls
            ]
        }
      foreignPath   = modPath runtimePkg "foreign"
      pkgModule     = FileInput
        { fiImports = [importAnn]
        , fiContent = []
        }
      pkgPath       = modPath packagePrefix "__init__"
      modPath ns n  = modulePath $ NonEmpty.fromList $ ns <> [n]
      f name funcs  = SCD ClassDef
        { cdDecorators = []
        , cdName       = name
        , cdArgs       = arg [eAbc, mTyping `EAttr` "Generic" `ESub` [tS]]
        , cdSuite      = funcs
        }
  pure allFiles

makeModule :: GuguguK r m
           => Module
           -> m (ForeignTypeResult, (FilePath, FileInput))
makeModule md@Module{..} = do
  GuguguPythonOption{..} <- asks toGuguguPythonOption
  importsAndTypeDecs <- traverse (makeData md) moduleDatas
  transComps <- if (withServer || withClient) && not (null moduleFuncs)
    then makeTransport md
    else pure mempty
  mod' <- mkModuleCode md
  let ((imports, foreigns), typeDecs) = fold importsAndTypeDecs
  let (iTyping, eTypeVar) = importItem $ "typing" :| ["TypeVar"]
  let moduleBody   = FileInput
        { fiImports = importAnn : Set.toAscList iAll
        , fiContent = sAll
        }
      path         = modulePath mod'
      (iAll, sAll) = codecPre <> mainBody <> transComps
      mainBody     = (imports, typeDecs)
      codecPre     = if withCodec
        then (iTyping, [sTv "S", sTv "R"]) else mempty
      sTv name     = SA AssignmentStmt
        { asTarget = TSimple name
        , asValue  = eTypeVar `eCall` [ESimple $ unsafeQuote name]
        }
  pure (foreigns, (path, moduleBody))

makeData :: GuguguK r m
         => Module
         -> Data
         -> m (ImportsAndForeign, [Statement])
makeData md d@Data{..} = do
  GuguguPythonOption{..} <- asks toGuguguPythonOption
  dataCode <- mkTypeCode d
  (imports, maybeDec) <- case dataConDef of
    Just (DRecord RecordCon{..}) -> do
      importAndfieldStmts <- for recordConFields $ \rf@RecordField{..} -> do
        fieldCode <- mkFieldCode rf
        (iField, pyType) <- makeType recordFieldType
        let stmt = SAA AnnotatedAssignmentStmt
              { aasTarget     = TSimple fieldCode
              , aasAnnotation = pyType
              }
        pure (iField, stmt)
      let classDef              = ClassDef
            { cdDecorators = [dataclass `eCall` []]
            , cdName       = dataCode
            , cdArgs       = noArg
            , cdSuite      = fieldStmts
            }
          (iDc, dataclass)      = importItem $ "dataclasses" :| ["dataclass"]
          (iFields, fieldStmts) = unzip importAndfieldStmts
      pure (fold iFields <> iDc, Just classDef)
    Just (DEnum names)           -> do
      stmts <- for (indexed $ toList names) $ \(i, name) -> do
        enumCode <- mkEnumCode name
        let stmt = SA AssignmentStmt
              { asTarget = TSimple enumCode
              , asValue  = ESimple $ showText i
              }
        pure stmt
      let classDef          = ClassDef
            { cdDecorators = []
            , cdName       = dataCode
            , cdArgs       = arg [tIntEnum]
            , cdSuite      = stmts
            }
          (iEnum, tIntEnum) = importItem $ "enum" :| ["IntEnum"]
      pure (iEnum, Just classDef)
    Nothing                      -> pure (Set.empty, Nothing)
  (foreigns', codecs) <- if withCodec then makeCodecDefs md d else pure mempty
  let decs       = if null codecs then toList maybeDec else [withCodecs]
      withCodecs = clazz{ cdSuite = cdSuite clazz <> codecs }
      clazz      = fromMaybe defaultDec maybeDec
      defaultDec = ClassDef
        { cdDecorators = []
        , cdName       = dataCode <> "Codec"
        , cdArgs       = noArg
        , cdSuite      = []
        }
  pure ((imports, mempty) <> foreigns', fmap SCD decs)

makeCodecDefs :: GuguguK r m
              => Module
              -> Data
              -> m (ImportsAndForeign, [Statement])
makeCodecDefs Module{..} d@Data{..} = do
  GuguguPythonOption{..} <- asks toGuguguPythonOption
  (iThis, tThis) <- resolveLocalPythonType d
  encodeName <- mkTypeFunc $ "encode" <> dataName
  decodeName <- mkTypeFunc $ "decode" <> dataName
  let eA                 = ESimple "a"
      pCls               = ("cls", Nothing)
      eS                 = ESimple "s"
      pS                 = ("s", Just tS)
      tR                 = ESimple "R"
      tDecodeR           = Just $ mTyping `EAttr` "Tuple" `ESub` [tS, tThis]
      (iCodec, mCodec)   = importModule $ NonEmpty.fromList $
        runtimePkg <> ["codec"]
      (iTyping, mTyping) = importModule $ "typing" :| []
  (foreigns, iCodecs, encodeStmts, decodeStmts) <- case dataConDef of
    Just (DRecord RecordCon{..}) -> do
      let eS1      = ESimple "s1"
          eLambda' = eLambda1 "s2"
      codecComps <- for (indexed recordConFields) $ \(i, rf) -> do
        fieldCode <- mkFieldCode rf
        fieldValue <- mkFieldValue rf
        (iField, (encoder, decoder)) <- makeCodecExpr $ recordFieldType rf
        let encodeS = SA AssignmentStmt
              { asTarget = TSimple "s1"
              , asValue  = eImpl `EAttr` "encode_record_field" `eCall`
                  [ eS1, eI, fieldValue
                  , eLambda' $ \s2 ->
                      encoder `eCall` [s2 , eA `EAttr` fieldCode, eImpl]
                  ]
              }
            decodeS = SA AssignmentStmt
              { asTarget = TTwo "s1" vi
              , asValue  = eImpl `EAttr` "decode_record_field" `eCall`
                  [ eS1, eI, fieldValue
                  , eLambda' $ \s2 -> decoder `eCall` [s2, eImpl]
                  ]
              }
            eI      = ESimple $ showText i
            eVi     = ESimple vi
            vi      = "v" <> showText i
        pure (iField, encodeS, decodeS, eVi)
      let (iFields, encodeStmts, decodeStmts, fields) =
            List.unzip4 codecComps
      let encodeDef       = [encodeFieldsDef, fDef "encode_record"]
          decodeDef       = [decodeFieldsDef, fDef "decode_record"]
          encodeFieldsDef = fK $ encodeStmts <> [sReturn eS1]
          decodeFieldsDef = fK $ decodeStmts <> [sR]
            where sR = SR ReturnStmt
                    { rsValues = [eS1, tThis `eCall` fields]
                    }
          fDef attr       = sReturn $ eImpl `EAttr` attr `eCall` params
          fK suite        = SFD FuncDef
            { fdDecorators = []
            , fdName       = "k"
            , fdParams     = [("s1", Nothing)]
            , fdRType      = Nothing
            , fdSuite      = suite
            }
          params          =
            [eS, ESimple $ showText (length recordConFields), eK]
      pure (mempty, fold iFields, encodeDef, decodeDef)
    Just (DEnum names)           -> do
      vnPairs <- for names $ \name -> do
        enumCode <- mkEnumCode name
        enumValue <- mkEnumValue name
        pure (tThis `EAttr` enumCode, enumValue)
      let encodeDef  = sReturn $ eImpl `EAttr` "encode_enum" `eCall`
            [ eS
            , eA
            , eLambda1 "a1" $ \a -> a `EAttr` "value"
            , eLambda1 "a1" $ \a -> EDict (toList vnPairs) `ESub` [a]
            ]
          decodeDef  = sReturn $ eImpl `EAttr` "decode_enum" `eCall`
            [ eS
            , ESimple "by_index"
            , eLambda1 "n" $ \n ->
                EDict (fmap swap $ toList vnPairs) `EAttr` "get" `eCall` [n]
            ]
          byIndexDef = SFD FuncDef
            { fdDecorators = []
            , fdName       = "by_index"
            , fdParams     = [("i", Nothing)]
            , fdRType      = Nothing
            , fdSuite      =
                [ ST TryStmt
                    { tsBody    = [sReturn $ tThis `eCall` [ESimple "i"]]
                    , tsExcepts =
                        [(ESimple "ValueError", Nothing, [sReturn eNone])]
                    , tsElse    = Nothing
                    , tsFinally = Nothing
                    }
                ]
            }
      pure (mempty, Set.empty, [encodeDef], [byIndexDef, decodeDef])
    Nothing                      -> do
      let qualForeignName = if moduleName == "Foreign"
            then dataName else moduleName <> dataName
      encodeImplName <- mkTypeFunc $ "encode" <> qualForeignName
      decodeImplName <- mkTypeFunc $ "decode" <> qualForeignName
      let (iAbc, eAbstract) = importItem $ "abc" :| ["abstractmethod"]
      let encodeFDef = sReturn $ eImpl `EAttr` encodeImplName `eCall` [eS, eA]
          decodeFDef = sReturn $ eImpl `EAttr` decodeImplName `eCall` [eS]
          foreigns'  = (iTyping <> iAbc <> iThis, ([encodeImpl], [decodeImpl]))
          encodeImpl = SFD FuncDef
            { fdDecorators = [eAbstract]
            , fdName       = encodeImplName
            , fdParams     = [pSelf, pS, ("v", Just tThis)]
            , fdRType      = Just tS
            , fdSuite      = notImplemented
            }
          decodeImpl = SFD FuncDef
            { fdDecorators = [eAbstract]
            , fdName       = decodeImplName
            , fdParams     = [pSelf, pS]
            , fdRType      = tDecodeR
            , fdSuite      = notImplemented
            }
          pSelf      = ("self", Nothing)
      pure (foreigns', iThis, [encodeFDef], [decodeFDef])
  let allImports  = iCodec <> iThis <> iTyping <> iCodecs
      encoderDef  = SFD FuncDef
        { fdDecorators = dClassmethod
        , fdName       = encodeName
        , fdParams     =
            [pCls, pS, ("a", Just tThis), ("impl", Just tEncoderImpl)]
        , fdRType      = Just tS
        , fdSuite      = encodeStmts
        }
        where tEncoderImpl = mCodec `EAttr` "EncoderImpl" `ESub` [tS, tR]
      decoderDef  = SFD FuncDef
        { fdDecorators = dClassmethod
        , fdName       = decodeName
        , fdParams     = [pCls, pS, ("impl", Just tDecoderImpl)]
        , fdRType      = tDecodeR
        , fdSuite      = decodeStmts
        }
        where tDecoderImpl = mCodec `EAttr` "DecoderImpl" `ESub` [tS, tR]
  pure ((allImports, foreigns), [encoderDef, decoderDef])

makeTransport :: GuguguK r m => Module -> m (Set ImportStmt, [Statement])
makeTransport md@Module{..} = do
  GuguguPythonOption{..} <- asks toGuguguPythonOption
  let
      (cImports, mCodec)    = importModule $ NonEmpty.fromList $
        runtimePkg <> ["codec"]
      (tImports, mTrans)    = importModule $ NonEmpty.fromList $
        runtimePkg <> ["transport"]
      (iAbc, mAbc)          = importModule $ "abc" :| []
      dAbstract             = [mAbc `EAttr` "abstractmethod"]
      mkEncode encoder impl = eLambda1 "x" $ \x ->
        mCodec `EAttr` "encode" `eCall` [x, impl, encoder]
      mkDecode decoder impl = eLambda1 "r" $ \r ->
        mCodec `EAttr` "decode" `eCall` [r, impl, decoder]
      eNamespace            = ESimple "NAMESPACE"
  transportComps <- for moduleFuncs $ \fn@Func{..} -> do
    funcCode <- mkFuncCode fn
    funcValue <- mkFuncValue fn
    funcCodomain1 <- case funcCodomain of
      GApp{ typeCon = "IO", typeParams = [v] } -> pure v
      _                                        ->
        throwError "Function codomain must be a type like IO a"
    (iFd, (fdEncoder, fdDecoder)) <- makeCodecExpr funcDomain
    (iFcd, (fcdEncoder, fcdDecoder)) <- makeCodecExpr funcCodomain1
    let funcDec    = SFD FuncDef
          { fdDecorators = dAbstract
          , fdName       = funcCode
          , fdParams     = params
          , fdRType      = Nothing
          , fdSuite      = notImplemented
          }
        serverFunc = eLambda1 "k" $ \k -> eLambda1 "fr" $ \fr -> k `eCall`
            [ mkDecode fdDecoder $ ESimple "decoder_impl"
            , mkEncode fcdEncoder $ ESimple "encoder_impl"
            , eImpl `EAttr` funcCode
            , fr
            ]
        clientFunc = SFD FuncDef
          { fdDecorators = []
          , fdName       = funcCode
          , fdParams     = params
          , fdRType      = Nothing
          , fdSuite      =
              [ sReturn $ eSelf `EAttr` "_t" `EAttr` "send" `eCall`
                  [ mTrans `EAttr` "QualName" `eCall` [eNamespace, funcValue]
                  , mkEncode fdEncoder $ eSelf `EAttr` "_e"
                  , mkDecode fcdDecoder $ eSelf `EAttr` "_d"
                  , ESimple "fa"
                  ]
              ]
          }
        params     = [("self", Nothing), ("fa", Nothing)]
    pure (iFd <> iFcd, funcDec, (funcValue, serverFunc), clientFunc)
  let (imports, funcDecs, serverCases, clientFuncs) =
        List.unzip4 transportComps
  className <- mkModuleType md "Module"
  moduelValue <- mkModuleValue md
  let allDecs          = [classDef]
                      <> [serverClass | withServer]
                      <> [clientClass | withClient]
                      <> [nsDef]
      allImports       = tImports <> cImports <> iAbc <> fold imports
      classDef         = SCD ClassDef
        { cdDecorators = []
        , cdName       = className
        , cdArgs       = arg [mAbc `EAttr` "ABC"]
        , cdSuite      = funcDecs
                      <> [toTransportDef | withServer]
                      <> [fromTransportDef | withClient]
        }
      toTransportDef   = SFD FuncDef
        { fdDecorators = dClassmethod
        , fdName       = "to_transport"
        , fdParams     =
            [ ("cls", Nothing)
            , ("impl", Just $ ESimple className)
            , ("decoder_impl", Nothing)
            , ("encoder_impl", Nothing)
            ]
        , fdRType      = Just $ mTrans `EAttr` "ServerTransport"
        , fdSuite      =
            [sReturn $ ESimple serverName `eCall` [EDict serverCases]]
        }
      fromTransportDef = SFD FuncDef
        { fdDecorators = dClassmethod
        , fdName       = "from_transport"
        , fdParams     =
            [ ("cls", Nothing)
            , ("transport", Nothing)
            , ("encoder_impl", Nothing)
            , ("decoder_impl", Nothing)
            ]
        , fdRType      = Just $ ESimple className
        , fdSuite      =
            [ sReturn $ ESimple clientName `eCall`
                [ ESimple "transport"
                , ESimple "encoder_impl"
                , ESimple "decoder_impl"
                ]
            ]
        }
      serverClass      = SCD ClassDef
        { cdDecorators = []
        , cdName       = serverName
        , cdArgs       = arg [mTrans `EAttr` "ServerTransport"]
        , cdSuite      =
            [ SFD FuncDef
                { fdDecorators = []
                , fdName       = "__init__"
                , fdParams     = [("self", Nothing), ("handler_map", Nothing)]
                , fdRType      = Nothing
                , fdSuite      = [assignSelf "_handler_map" "handler_map"]
                }
            , SFD FuncDef
                { fdDecorators = []
                , fdName       = "ask"
                , fdParams     =
                    [("self", Nothing), ("name", Nothing), ("k", Nothing)]
                , fdRType      = Nothing
                , fdSuite      =
                    [ SI IfStmt
                        { isCond  = EBinary
                            (eName `EAttr` "namespace") "!=" eNamespace
                        , isFirst = [sReturn eNone]
                        }
                    , SA AssignmentStmt
                        { asTarget = TSimple "handler"
                        , asValue  =
                            eSelf `EAttr` "_handler_map" `EAttr` "get"
                            `eCall` [eName `EAttr` "name"]
                        }
                    , SI IfStmt
                        { isCond  = EBinary (ESimple "handler") "is not" eNone
                        , isFirst = [sReturn $ ESimple "handler" `eCall` [eK]]
                        }
                    , sReturn eNone
                    ]
                }
            ]
        }
        where eName = ESimple "name"
      clientClass      = SCD ClassDef
        { cdDecorators = []
        , cdName       = clientName
        , cdArgs       = arg [ESimple className]
        , cdSuite      =
            [ SFD FuncDef
                { fdDecorators = []
                , fdName       = "__init__"
                , fdParams     =
                    [ ("self", Nothing)
                    , ("transport", Nothing)
                    , ("encoder_impl", Nothing)
                    , ("decoder_impl", Nothing)
                    ]
                , fdRType      = Nothing
                , fdSuite      =
                    [ assignSelf "_t" "transport"
                    , assignSelf "_e" "encoder_impl"
                    , assignSelf "_d" "decoder_impl"
                    ]
                }
            ] <> clientFuncs
        }
      nsDef            = SA AssignmentStmt
        { asTarget = TSimple "NAMESPACE"
        , asValue  = moduelValue
        }
      clientName       = "_" <> className
      serverName       = "_ServerTransport"
      assignSelf n v   = SA AssignmentStmt
        { asTarget = eSelf `TAttr` n
        , asValue  = ESimple v
        }
  pure (allImports, allDecs)


makeType :: GuguguK r m => GType -> m (Set ImportStmt, Expr)
makeType GApp{..} = do
  rFirst@(imports, tFirst) <- resolvePythonType typeCon
  if null typeParams
    then pure rFirst
    else do
      importsAndParams <- traverse makeType typeParams
      let pType              = ESub tFirst params
          allImports         = fold imports' `Set.union` imports
          (imports', params) = unzip importsAndParams
      pure (allImports, pType)

makeCodecExpr :: GuguguK r m => GType -> m (Set ImportStmt, (Expr, Expr))
makeCodecExpr GApp{..} = do
  codecAndImports@(imports, (encoderF, decoderF)) <- resolveTypeCodec typeCon
  if null typeParams
    then pure codecAndImports
    else do
      importsAndParams <- traverse makeCodecExpr typeParams
      let encoder                = encoderF `eCall` encoderPs
          decoder                = decoderF `eCall` decoderPs
          allImports             = fold imports' `Set.union` imports
          (imports', params)     = unzip importsAndParams
          (encoderPs, decoderPs) = unzip params
      pure (allImports, (encoder, decoder))

resolvePythonType :: GuguguK r m => Text -> m (Set ImportStmt, Expr)
resolvePythonType t = do
  rr <- resolveTypeCon t
  case rr of
    ResolutionError e -> throwError e
    LocalType d       -> resolveLocalPythonType d
    Imported md d     -> case dataConDef d of
      Nothing -> resolveForeign' d
      Just _  -> do
        modName <- mkModuleCode md
        typeName <- mkTypeCode d
        pure $ importItem $ modName <> (typeName :| [])
    Primitive pt      -> do
      let simple t' = (Set.empty, ESimple t')
          typing t' = importItem ("typing" :| [t'])
      pure $ case pt of
        PUnit   -> simple "object"
        PBool   -> simple "bool"
        PInt32  -> simple "int"
        PDouble -> simple "float"
        PString -> simple "str"
        PMaybe  -> typing "Optional"
        PList   -> typing "List"

resolveTypeCodec :: GuguguK r m => Text -> m (Set ImportStmt, (Expr, Expr))
resolveTypeCodec t = do
  rr <- resolveTypeCon t
  (encoderQName, decoderQName) <- case rr of
    ResolutionError e -> throwError e
    LocalType d       -> do
      n <- mkTypeCode d
      let qName = case dataConDef d of
            Just _  -> n :| []
            Nothing -> (n <> "Codec") :| []
      pure (qName, qName)
    Imported md d     -> do
      modName <- mkModuleCode md
      n <- mkTypeCode d
      let qName = modName <> case dataConDef d of
            Just _  -> n :| []
            Nothing -> (n <> "Codec") :| []
      pure (qName, qName)
    Primitive _       -> do
      GuguguPythonOption{..} <- asks toGuguguPythonOption
      let f n = NonEmpty.fromList $ runtimePkg <> ["codec", n]
      pure (f "Encoders", f "Decoders")
  let f p qName = do
        funcName <- mkTypeFunc $ p <> t
        let (imports, eType) = importItem qName
        pure (imports, eType `EAttr` funcName)
  liftA2 (liftA2 (,)) (f "encode" encoderQName) (f "decode" decoderQName)

resolveLocalPythonType :: GuguguK r m => Data -> m (Set ImportStmt, Expr)
resolveLocalPythonType d@Data{..} = case dataConDef of
  Nothing -> resolveForeign' d
  Just _  -> do
    typeName <- mkTypeCode d
    pure (Set.empty, ESimple typeName)

resolveForeign' :: GuguguK r m => Data -> m (Set ImportStmt, Expr)
resolveForeign' Data{..} = do
  foreignPragma <- case Map.lookup thisTarget dataForeignMap of
    Just v  -> pure v
    Nothing -> throwError $ printf
      "Type %s does not have foreign pragma" dataName
  case NonEmpty.nonEmpty $ splitOn' "." foreignPragma of
    Nothing -> throwError $ printf "Bad FOREIGN pragma: %s" foreignPragma
    Just qn -> pure $ importItem qn

modulePath :: NonEmpty Identifier -> FilePath
modulePath (part1 :| parts) = path <.> "py"
  where
    path = foldl' (\z t -> z </> T.unpack t) (T.unpack part1) parts


-- Name transformers

mkModuleCode :: GuguguK r m => Module -> m (NonEmpty Identifier)
mkModuleCode Module{..} = do
  GuguguPythonOption{..} <- asks toGuguguPythonOption
  withTransformer transModuleCode $ \f ->
    NonEmpty.fromList $ packagePrefix <> [f moduleName]

mkModuleValue :: GuguguK r m => Module -> m Expr
mkModuleValue Module{..} = withTransformer transModuleValue $ \f ->
  EList [ESimple $ unsafeQuote $ f moduleName]

mkModuleType :: GuguguK r m => Module -> Text -> m Text
mkModuleType Module{..} suffix = withTransformer transModuleType $ \f ->
  f $ moduleName <> suffix

mkFuncCode :: GuguguK r m => Func -> m Text
mkFuncCode Func{..} = withTransformer transFuncCode $ \f ->
  f funcName

mkFuncValue :: GuguguK r m => Func -> m Expr
mkFuncValue Func{..} = withTransformer transFuncValue $ \f ->
  ESimple $ unsafeQuote $ f funcName

mkTypeCode :: GuguguK r m => Data -> m Text
mkTypeCode Data{..} = withTransformer transTypeCode $ \f ->
  f dataName

mkTypeFunc :: GuguguK r m => Text -> m Text
mkTypeFunc name = withTransformer transTypeFunc $ \f ->
  f name

mkFieldCode :: GuguguK r m => RecordField -> m Text
mkFieldCode RecordField{..} = withTransformer transFieldCode $ \f ->
  f recordFieldName

mkFieldValue :: GuguguK r m => RecordField -> m Expr
mkFieldValue RecordField{..} = withTransformer transFieldValue $ \f ->
  ESimple $ unsafeQuote $ f recordFieldName

mkEnumCode :: GuguguK r m => Text -> m Text
mkEnumCode name = withTransformer transEnumCode $ \f ->
  f name

mkEnumValue :: GuguguK r m => Text -> m Expr
mkEnumValue name = withTransformer transEnumValue $ \f ->
  ESimple $ unsafeQuote $ f name


-- Utilities

thisTarget :: Text
thisTarget = "python"

importAnn :: ImportStmt
importAnn = ImportFrom ("__future__" :| []) ("annotations" :| [])

eCall :: Expr -> [Expr] -> Expr
eCall func args = func `ECall` arg args

eLambda1 :: Text -> (Expr -> Expr) -> Expr
eLambda1 argName = \f -> ELambda LambdaExpr
  { leParams = [argName]
  , leExpr   = f eArg
  }
  where eArg = ESimple argName

sReturn :: Expr -> Statement
sReturn expr = SR ReturnStmt
  { rsValues = [expr]
  }

noArg :: ArgumentList
noArg = arg []

arg :: [Expr] -> ArgumentList
arg vs = ArgumentList
  { alPositional = vs
  }

importModule :: NonEmpty Identifier -> (Set ImportStmt, Expr)
importModule modName = (Set.singleton (ImportAs modName alias), ESimple alias)
  where alias = mkGuguguImportAlias modName

importItem :: NonEmpty Identifier -> (Set ImportStmt, Expr)
importItem qName = case NonEmpty.nonEmpty $ NonEmpty.init qName of
  Just mod' -> second (`EAttr` NonEmpty.last qName) (importModule mod')
  Nothing   -> (Set.empty, ESimple $ NonEmpty.head qName)

mkGuguguImportAlias :: NonEmpty Identifier -> Identifier
mkGuguguImportAlias ps = "_gugugu_i_" <> T.intercalate "_" (toList ps)

withTransformer :: GuguguK r m
                => (GuguguNameTransformers -> NameTransformer)
                -> ((Text -> Text) -> a)
                -> m a
withTransformer selector k = do
  nt <- asks $ selector . nameTransformers . toGuguguPythonOption
  pure . k $ runNameTransformer nt

eNone :: Expr
eNone = ESimple "None"

eSelf :: Expr
eSelf = ESimple "self"

eImpl :: Expr
eImpl = ESimple "impl"

eK :: Expr
eK = ESimple "k"

tS :: Expr
tS = ESimple "S"

notImplemented :: [Statement]
notImplemented = [SRA $ RaiseStmt $ ESimple "NotImplementedError"]

dClassmethod :: [Expr]
dClassmethod = [ESimple "classmethod"]


-- Instances

instance HasGuguguPythonOption GuguguPythonEnv where
  toGuguguPythonOption = gOpts

instance HasResolutionContext GuguguPythonEnv where
  toResolutionContext = gCtx
