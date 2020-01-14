{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveLift                 #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE StandaloneDeriving         #-}

module Data.Morpheus.Types.Internal.AST.Base
  ( Key
  , Collection
  , Ref(..)
  , Position(..)
  , Message
  , Name
  , Description
  , VALID
  , RAW
  , TypeWrapper(..)
  , Stage(..)
  , RESOLVED
  , TypeRef(..)
  , VALIDATION_MODE(..)
  , OperationType(..)
  , QUERY
  , MUTATION
  , SUBSCRIPTION
  , DataTypeKind(..)
  , DataFingerprint(..)
  , DataTypeWrapper(..)
  , GQLMap(..)
  , Empty(..)
  , Selectable(..)
  , Listable(..)
  , anonymousRef
  , uniqueElemOr
  , elementOfKeys
  , toHSWrappers
  , toGQLWrapper
  , sysTypes
  , isNullable
  , isWeaker
  , isSubscription
  , isOutputObject
  , isDefaultTypeName
  , isSchemaTypeName
  , isPrimitiveTypeName
  , isObject
  , isInput
  , isNullableWrapper
  , isOutputType
  , sysFields
  , typeFromScalar
  , hsTypeName
  , toOperationType
  , splitDuplicates
  , removeDuplicates
  )
where

import           Data.Semigroup                 ((<>))
import           Data.Aeson                     ( FromJSON
                                                , ToJSON
                                                )
import           Data.Text                      ( Text )
import           GHC.Generics                   ( Generic )
import           Language.Haskell.TH.Syntax     ( Lift(..) )
import           Instances.TH.Lift              ( )
import           Data.HashMap.Lazy              ( HashMap )
import qualified Data.HashMap.Lazy             as HM 

type Key = Text
type Message = Text
type Name = Key
type Description = Key
type Collection a = [(Key, a)]
data Stage = RAW | RESOLVED | VALID

type RAW = 'RAW

type RESOLVED = 'RESOLVED

type VALID = 'VALID

data Position = Position
  { line   :: Int
  , column :: Int
  } deriving (Show, Generic, FromJSON, ToJSON, Lift)

data VALIDATION_MODE
  = WITHOUT_VARIABLES
  | FULL_VALIDATION
  deriving (Eq, Show)

data DataFingerprint = DataFingerprint Name [String] deriving (Show, Eq, Ord, Lift)

data OperationType
  = Query
  | Subscription
  | Mutation
  deriving (Show, Eq, Lift)

type QUERY = 'Query
type MUTATION = 'Mutation
type SUBSCRIPTION = 'Subscription

data Named a 
  = Named 
  {
    uniqName :: Name,
    unName :: a
  } deriving 
    ( Show
    , Lift
    , Functor
    , Foldable
    )

instance Traversable Named where
  traverse f Named { uniqName, unName } = Named uniqName <$> f unName

class Empty a where 
  empty :: a

instance Empty (HashMap k v) where
  empty = HM.empty

class Selectable c a where 
  selectOr :: d -> (a -> d) -> Name -> c -> d

instance Selectable (GQLMap a) a where 
  -- selectOr fb f key GQLMap { mapValues } = maybe fb f (HM.lookup key mapValues)

instance Selectable [(Name, a)] a where 
  selectOr fb f key lib = maybe fb f (lookup key lib)

instance Selectable (HashMap Text a) a where 
  selectOr fb f key lib = maybe fb f (HM.lookup key lib)

class Listable c a where
  fromList   :: [a] ->  c
  toList     ::  c  -> [a]
  singleton  :: a -> c

-- GQLMap 
data GQLMap value   
  = GQLMap      { mapValues :: [Named value] }
  | GQLMapError { dupFields :: [Name]        }
  deriving (Show, Foldable)


validateValues :: [Named value] -> GQLMap value
validateValues values 
  | null dupNames = GQLMap noDups
  | otherwise = GQLMapError dupNames
 where (noDups,dupNames,_) = splitDupElem values

instance Functor GQLMap where
  -- and we hope no one changed keys 
  fmap f GQLMap { mapValues } = validateValues (fmap f <$> mapValues) 
  fmap _ GQLMapError { .. } = GQLMapError { .. } 

instance Semigroup (GQLMap a) where
  GQLMapError err1 <> GQLMapError err2 = GQLMapError (err1 <> err2)
  GQLMap _ <> GQLMapError name = GQLMapError name
  GQLMapError err1 <> GQLMap _ = GQLMapError err1
  GQLMap v1 <> GQLMap v2 = validateValues (v1 <> v2)

instance Traversable GQLMap where
  traverse _ (GQLMapError err1) = pure $ GQLMapError err1
  traverse f (GQLMap values) = GQLMap <$> traverse (traverse f) values

--instance Lift a => Lift (GQLMap a) where 
--  lift (GQLMap x y z) = [| GQLMap x (HM.fromList ys) z |] 
--    where ys = HM.toList y

instance Empty (GQLMap a) where 
  empty = GQLMap  []

instance Listable (GQLMap a) a where
  -- singleton x = GQLMap [uniqueKey x] (HM.singleton (uniqueKey x) x) []
  -- fromList xs = 
  --   GQLMap 
  --   { mapNames = map uniqueKey xs
  --   , mapValues = HM.fromList (map 
  --       (\x -> (uniqueKey x,x)) 
  --       uniqueXs) 
  --   , mapDups
  --   }
  --   where (uniqueXs,_,mapDups) = splitDupElem xs
  -- toList GQLMap { mapNames , mapValues } = maybe (error "TODO:error") id $ traverse (`HM.lookup` mapValues) mapNames


-- Refference with Position information  
--
-- includes position for debugging, where Ref "a" 1 === Ref "a" 3
--
data Ref = Ref
  { refName     :: Key
  , refPosition :: Position
  } deriving (Show,Lift)

instance Eq Ref where
  (Ref id1 _) == (Ref id2 _) = id1 == id2

instance Ord Ref where
  compare (Ref x _) (Ref y _) = compare x y

anonymousRef :: Key -> Ref
anonymousRef refName = Ref { refName, refPosition = Position 0 0 }


-- TypeRef
-------------------------------------------------------------------
data TypeRef = TypeRef
  { typeConName    :: Name
  , typeArgs     :: Maybe Name
  , typeWrappers :: [TypeWrapper]
  } deriving (Show,Lift)

isNullable :: TypeRef -> Bool
isNullable TypeRef { typeWrappers = typeWrappers } = isNullableWrapper typeWrappers

-- Kind
-----------------------------------------------------------------------------------
data DataTypeKind
  = KindScalar
  | KindObject (Maybe OperationType)
  | KindUnion
  | KindEnum
  | KindInputObject
  | KindList
  | KindNonNull
  | KindInputUnion
  deriving (Eq, Show, Lift)

isSubscription :: DataTypeKind -> Bool
isSubscription (KindObject (Just Subscription)) = True
isSubscription _ = False

isOutputType :: DataTypeKind -> Bool
isOutputType (KindObject _) = True
isOutputType KindUnion      = True
isOutputType _              = False

isOutputObject :: DataTypeKind -> Bool
isOutputObject (KindObject _) = True
isOutputObject _              = False

isObject :: DataTypeKind -> Bool
isObject (KindObject _)  = True
isObject KindInputObject = True
isObject _               = False

isInput :: DataTypeKind -> Bool
isInput KindInputObject = True
isInput _               = False



-- TypeWrappers
-----------------------------------------------------------------------------------
data TypeWrapper
  = TypeList
  | TypeMaybe
  deriving (Show, Lift)

data DataTypeWrapper
  = ListType
  | NonNullType
  deriving (Show, Lift)

isNullableWrapper :: [TypeWrapper] -> Bool
isNullableWrapper (TypeMaybe : _ ) = True
isNullableWrapper _               = False

isWeaker :: [TypeWrapper] -> [TypeWrapper] -> Bool
isWeaker (TypeMaybe : xs1) (TypeMaybe : xs2) = isWeaker xs1 xs2
isWeaker (TypeMaybe : _  ) _                 = True
isWeaker (_         : xs1) (_ : xs2)         = isWeaker xs1 xs2
isWeaker _                 _                 = False

toGQLWrapper :: [TypeWrapper] -> [DataTypeWrapper]
toGQLWrapper (TypeMaybe : (TypeMaybe : tw)) = toGQLWrapper (TypeMaybe : tw)
toGQLWrapper (TypeMaybe : (TypeList  : tw)) = ListType : toGQLWrapper tw
toGQLWrapper (TypeList : tw) = [NonNullType, ListType] <> toGQLWrapper tw
toGQLWrapper [TypeMaybe                   ] = []
toGQLWrapper []                             = [NonNullType]

toHSWrappers :: [DataTypeWrapper] -> [TypeWrapper]
toHSWrappers (NonNullType : (NonNullType : xs)) =
  toHSWrappers (NonNullType : xs)
toHSWrappers (NonNullType : (ListType : xs)) = TypeList : toHSWrappers xs
toHSWrappers (ListType : xs) = [TypeMaybe, TypeList] <> toHSWrappers xs
toHSWrappers []                              = [TypeMaybe]
toHSWrappers [NonNullType]                   = []

elementOfKeys :: [Name] -> Ref -> Bool
elementOfKeys keys Ref { refName } = refName `elem` keys

isDefaultTypeName :: Key -> Bool
isDefaultTypeName x = isSchemaTypeName x || isPrimitiveTypeName x

isSchemaTypeName :: Key -> Bool
isSchemaTypeName = (`elem` sysTypes)

isPrimitiveTypeName :: Key -> Bool
isPrimitiveTypeName = (`elem` ["String", "Float", "Int", "Boolean", "ID"])

sysTypes :: [Key]
sysTypes =
  [ "__Schema"
  , "__Type"
  , "__Directive"
  , "__TypeKind"
  , "__Field"
  , "__DirectiveLocation"
  , "__InputValue"
  , "__EnumValue"
  ]

sysFields :: [Key]
sysFields = ["__typename","__schema","__type"]

typeFromScalar :: Name -> Name
typeFromScalar "Boolean" = "Bool"
typeFromScalar "Int"     = "Int"
typeFromScalar "Float"   = "Float"
typeFromScalar "String"  = "Text"
typeFromScalar "ID"      = "ID"
typeFromScalar _         = "ScalarValue"

hsTypeName :: Key -> Key
hsTypeName "String"                    = "Text"
hsTypeName "Boolean"                   = "Bool"
hsTypeName name | name `elem` sysTypes = "S" <> name
hsTypeName name                        = name

toOperationType :: Name -> Maybe OperationType
toOperationType "Subscription" = Just Subscription
toOperationType "Mutation" = Just Mutation
toOperationType "Query" = Just Query
toOperationType _ = Nothing

-- validation combinators
uniqueElemOr :: (Applicative validation, Eq a) 
  => ([a]-> validation [a])
  ->  [a] -> validation [a]
uniqueElemOr fallback ls = case splitDuplicates ls of
      (collected,[]) -> pure collected
      (_,errors) -> fallback errors

removeDuplicates :: Eq a => [a] -> [a]
removeDuplicates = fst . splitDuplicates

-- elems -> (unique elements, duplicate elems)
splitDuplicates :: Eq a => [a] -> ([a],[a])
splitDuplicates = collectElems ([],[])
  where
    collectElems :: Eq a => ([a],[a]) -> [a] -> ([a],[a])
    collectElems collected [] = collected
    collectElems (collected,errors) (x:xs)
        | x `elem` collected = collectElems (collected,errors <> [x]) xs
        | otherwise = collectElems (collected <> [x],errors) xs


splitDupElem :: [Named a] -> ([Named a],[Name],[Named a])
splitDupElem = collectElems ([],[],[])
  where
    collectElems :: ([Named a],[Name],[Named a]) -> [Named a] -> ([Named a],[Name],[Named a])
    collectElems collected [] = collected
    collectElems (values,names,errors) (x:xs)
        | uniqName x `elem` names = collectElems (values,names <> [uniqName x],errors <> [x]) xs
        | otherwise = collectElems (values <> [x],names,errors) xs
