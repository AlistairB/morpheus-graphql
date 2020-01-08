{-# LANGUAGE OverloadedStrings      #-}
{-# LANGUAGE KindSignatures         #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE MultiParamTypeClasses  #-}

module Data.Morpheus.Types.TypeSystemDirective
  ( TypeSystemDirective(..)
  )
where

import           Data.Morpheus.Types.Internal.AST.Data
                                                  ( DataType, 
                                                    DataField 
                                                  )

data TypeSystemDirectiveLocation 
  = SCHEMA
  | SCALAR
  | OBJECT
  | FIELD_DEFINITION
  | ARGUMENT_DEFINITION
  | INTERFACE
  | UNION
  | ENUM
  | ENUM_VALUE
  | INPUT_OBJECT
  | INPUT_FIELD_DEFINITION


type family ASTByLocation ( loc :: TypeSystemDirectiveLocation) :: * 
type instance ASTByLocation 'FIELD_DEFINITION = DataField


-- TODO: implement directive Decoder
-- TODO: find out how to implement default resolving on Fields with directive. 

-- | GraphQL TypeSystemDirective
-- https://graphql.github.io/graphql-spec/June2018/#sec-Type-System.Directives
-- 
class TypeSystemDirective (loc :: TypeSystemDirectiveLocation ) directive where
  applyDSL :: proxy loc -> directive -> ASTByLocation loc -> ASTByLocation loc