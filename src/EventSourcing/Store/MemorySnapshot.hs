module EventSourcing.Store.MemorySnapshot
  ( MemorySnapshotStore
  , memorySnapshotStore
  ) where

import Control.Concurrent.STM
import Control.Monad.IO.Class
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.List (foldl')

import EventSourcing.Projection
import EventSourcing.Store.Class
import EventSourcing.UUID

-- | Wraps a given event store and stores the latest projections in memory.
data MemorySnapshotStore m store serialized proj
  = MemorySnapshotStore
  { _memorySnapshotStoreEventStore :: SerializedEventStore m store serialized (Event proj) => store
  -- TODO: Make the value type (EventVersion, ByteString) and use this for
  -- latestEventVersion.
  , _memorySnapshotStoreProjections :: TVar (Map UUID proj)
  }

memorySnapshotStore :: (MonadIO m) => store -> m (MemorySnapshotStore m store serialized proj)
memorySnapshotStore store = do
  tvar <- liftIO . atomically $ newTVar Map.empty
  return $ MemorySnapshotStore store tvar

getSnapshotProjection :: (Projection proj) => MemorySnapshotStore m store serialized proj -> UUID -> STM proj
getSnapshotProjection (MemorySnapshotStore _ tvar) uuid =
    fromMaybe seed . Map.lookup uuid <$> readTVar tvar

instance
  (Projection proj, Event proj ~ event, MonadIO m, SerializedEventStore m store serialized event)
  => SerializedEventStore m (MemorySnapshotStore m store serialized proj) serialized event where
  getSerializedEvents (MemorySnapshotStore store _) = getSerializedEvents store
  getAllSerializedEvents (MemorySnapshotStore store _) = getAllSerializedEvents store
  storeSerializedEvents mstore@(MemorySnapshotStore store tvar) uuid events = do
    storedEvents <- storeSerializedEvents store uuid events
    liftIO . atomically $ do
      proj <- getSnapshotProjection mstore uuid
      let proj' = foldl' apply proj events
      modifyTVar' tvar (Map.insert uuid (serialize proj'))
    return storedEvents

instance
  (MonadIO m, Projection proj, SerializedEventStore m store serialized (Event proj))
  => CachedEventStore m (MemorySnapshotStore m store serialized proj) serialized proj where
  getAggregate store (AggregateId uuid) = liftIO . atomically $ getSnapshotProjection store uuid
