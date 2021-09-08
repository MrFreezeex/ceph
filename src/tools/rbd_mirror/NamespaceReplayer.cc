// -*- mode:C++; tab-width:8; c-basic-offset:2; indent-tabs-mode:t -*-
// vim: ts=8 sw=2 smarttab

#include "NamespaceReplayer.h"
#include "common/Formatter.h"
#include "common/debug.h"
#include "common/errno.h"
#include "cls/rbd/cls_rbd_client.h"
#include "librbd/Utils.h"
#include "librbd/api/Config.h"
#include "librbd/api/Mirror.h"
#include "librbd/asio/ContextWQ.h"
#include "PoolMetaCache.h"
#include "ServiceDaemon.h"
#include "Threads.h"

#define dout_context g_ceph_context
#define dout_subsys ceph_subsys_rbd_mirror
#undef dout_prefix
#define dout_prefix *_dout << "rbd::mirror::NamespaceReplayer: " \
                           << this << " " << __func__ << ": "

using librbd::util::create_async_context_callback;
using librbd::util::create_context_callback;

namespace rbd {
namespace mirror {

using ::operator<<;

namespace {

const std::string SERVICE_DAEMON_LOCAL_COUNT_KEY("image_local_count");
const std::string SERVICE_DAEMON_REMOTE_COUNT_KEY("image_remote_count");

} // anonymous namespace

template <typename I>
NamespaceReplayer<I>::NamespaceReplayer(
    const std::string &name,
    librados::IoCtx &local_io_ctx,
    const std::string &local_mirror_uuid,
    Threads<I> *threads,
    Throttler<I> *image_sync_throttler,
    Throttler<I> *image_deletion_throttler,
    ServiceDaemon<I> *service_daemon,
    journal::CacheManagerHandler *cache_manager_handler,
    PoolMetaCache<I>* pool_meta_cache) :
  m_namespace_name(name),
  m_local_mirror_uuid(local_mirror_uuid),
  m_threads(threads), m_image_sync_throttler(image_sync_throttler),
  m_image_deletion_throttler(image_deletion_throttler),
  m_service_daemon(service_daemon),
  m_cache_manager_handler(cache_manager_handler),
  m_pool_meta_cache(pool_meta_cache),
  m_lock(ceph::make_mutex(librbd::util::unique_lock_name(
      "rbd::mirror::NamespaceReplayer " + name, this))),
  m_local_pool_watcher_listener(this, true),
  m_remote_pool_watcher_listener(this, false),
  m_image_map_listener(this) {
  dout(10) << name << dendl;

  m_local_io_ctx.dup(local_io_ctx);
  m_local_io_ctx.set_namespace(name);
}

template <typename I>
bool NamespaceReplayer<I>::is_blocklisted() const {
  std::lock_guard locker{m_lock};
  if (m_instance_replayer->is_blocklisted() ||
      (m_local_pool_watcher &&
       m_local_pool_watcher->is_blocklisted())) {
    return true;
  }

  for (const auto& kv_it : m_peers) {
    if (kv_it.second.pool_watcher &&
        kv_it.second.pool_watcher->is_blocklisted()) {
      return true;
    }
  }

  return false;
}

template <typename I>
void NamespaceReplayer<I>::init(Context *on_finish) {
  dout(20) << dendl;

  std::lock_guard locker{m_lock};

  ceph_assert(m_on_finish == nullptr);
  m_on_finish = on_finish;

  init_local_status_updater();
}


template <typename I>
void NamespaceReplayer<I>::shut_down(Context *on_finish) {
  dout(20) << dendl;

  {
    std::lock_guard locker{m_lock};

    ceph_assert(m_on_finish == nullptr);
    m_on_finish = on_finish;
  }

  remove_peers(0);
}

template <typename I>
void NamespaceReplayer<I>::remove_peers(int r) {
  dout(20) << dendl;
  ceph_assert(r == 0);

  if (m_peers.size() == 0) {
    handle_shut_down();
    return;
  }

  Context *ctx = create_async_context_callback(
    m_threads->work_queue, create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::remove_peers>(this));
  remove_peer(m_peers.begin()->second, ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down() {
  dout(20) << dendl;

  auto ctx = new LambdaContext([this] (int r) {
    std::lock_guard locker{m_lock};
    ceph_assert(r == 0);
    stop_instance_replayer();
  });
  if (m_image_map != nullptr) {
    handle_release_leader(ctx);
    return;
  }
  ctx->complete(0);
}

template <typename I>
void NamespaceReplayer<I>::print_status(Formatter *f)
{
  dout(20) << dendl;

  ceph_assert(f);

  std::lock_guard locker{m_lock};

  m_instance_replayer->print_status(f);

  if (m_image_deleter) {
    f->open_object_section("image_deleter");
    m_image_deleter->print_status(f);
    f->close_section();
  }
}

template <typename I>
void NamespaceReplayer<I>::start()
{
  dout(20) << dendl;

  std::lock_guard locker{m_lock};

  m_instance_replayer->start();
}

template <typename I>
void NamespaceReplayer<I>::stop()
{
  dout(20) << dendl;

  std::lock_guard locker{m_lock};

  m_instance_replayer->stop();
}

template <typename I>
void NamespaceReplayer<I>::restart()
{
  dout(20) << dendl;

  std::lock_guard locker{m_lock};

  m_instance_replayer->restart();
}

template <typename I>
void NamespaceReplayer<I>::flush()
{
  dout(20) << dendl;

  std::lock_guard locker{m_lock};

  m_instance_replayer->flush();
}

template <typename I>
void NamespaceReplayer<I>::handle_update(const std::string &mirror_uuid,
                                         ImageIds &&added_image_ids,
                                         ImageIds &&removed_image_ids) {
  std::lock_guard locker{m_lock};

  if (!m_image_map) {
    dout(20) << "not leader" << dendl;
    return;
  }

  dout(10) << "mirror_uuid=" << mirror_uuid << ", "
           << "added_count=" << added_image_ids.size() << ", "
           << "removed_count=" << removed_image_ids.size() << dendl;

  m_service_daemon->add_or_update_namespace_attribute(
    m_local_io_ctx.get_id(), m_local_io_ctx.get_namespace(),
    SERVICE_DAEMON_LOCAL_COUNT_KEY, m_local_pool_watcher->get_image_count());

  size_t remote_count = 0;
  for (auto& kv : m_peers) {
    if (kv.second.pool_watcher) {
      remote_count += kv.second.pool_watcher->get_image_count();
    }
  }
  m_service_daemon->add_or_update_namespace_attribute(
    m_local_io_ctx.get_id(), m_local_io_ctx.get_namespace(),
    SERVICE_DAEMON_REMOTE_COUNT_KEY, remote_count);

  std::set<std::string> added_global_image_ids;
  for (auto& image_id : added_image_ids) {
    added_global_image_ids.insert(image_id.global_id);
  }

  std::set<std::string> removed_global_image_ids;
  for (auto& image_id : removed_image_ids) {
    removed_global_image_ids.insert(image_id.global_id);
  }

  m_image_map->update_images(mirror_uuid,
                             std::move(added_global_image_ids),
                             std::move(removed_global_image_ids));
}

template <typename I>
void NamespaceReplayer<I>::handle_acquire_leader(Context *on_finish) {
  dout(10) << dendl;

  m_instance_watcher->handle_acquire_leader();

  init_image_map(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_release_leader(Context *on_finish) {
  dout(10) << dendl;

  m_instance_watcher->handle_release_leader();
  shut_down_image_deleter(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_update_leader(
    const std::string &leader_instance_id) {
  dout(10) << "leader_instance_id=" << leader_instance_id << dendl;

  m_instance_watcher->handle_update_leader(leader_instance_id);
}

template <typename I>
void NamespaceReplayer<I>::handle_instances_added(
    const std::vector<std::string> &instance_ids) {
  dout(10) << "instance_ids=" << instance_ids << dendl;

  std::lock_guard locker{m_lock};

  if (!m_image_map) {
    return;
  }

  m_image_map->update_instances_added(instance_ids);
}

template <typename I>
void NamespaceReplayer<I>::handle_instances_removed(
    const std::vector<std::string> &instance_ids) {
  dout(10) << "instance_ids=" << instance_ids << dendl;

  std::lock_guard locker{m_lock};

  if (!m_image_map) {
    return;
  }

  m_image_map->update_instances_removed(instance_ids);
}

template <typename I>
void NamespaceReplayer<I>::init_local_status_updater() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(!m_local_status_updater);

  m_local_status_updater.reset(MirrorStatusUpdater<I>::create(
    m_local_io_ctx, m_threads, ""));
  auto ctx = create_context_callback<
    NamespaceReplayer<I>,
    &NamespaceReplayer<I>::handle_init_local_status_updater>(this);

  m_local_status_updater->init(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_init_local_status_updater(int r) {
  dout(10) << "r=" << r << dendl;

  std::lock_guard locker{m_lock};

  if (r < 0) {
    derr << "error initializing local mirror status updater: "
         << cpp_strerror(r) << dendl;

    m_local_status_updater.reset();
    ceph_assert(m_on_finish != nullptr);
    m_threads->work_queue->queue(m_on_finish, r);
    m_on_finish = nullptr;
    return;
  }

  init_instance_replayer();
}

template <typename I>
void NamespaceReplayer<I>::init_instance_replayer() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(!m_instance_replayer);

  m_instance_replayer.reset(InstanceReplayer<I>::create(
      m_local_io_ctx, m_local_mirror_uuid, m_threads, m_service_daemon,
      m_local_status_updater.get(), m_cache_manager_handler,
      m_pool_meta_cache));
  auto ctx = create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_init_instance_replayer>(this);

  m_instance_replayer->init(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_init_instance_replayer(int r) {
  dout(10) << "r=" << r << dendl;

  std::lock_guard locker{m_lock};

  if (r < 0) {
    derr << "error initializing instance replayer: " << cpp_strerror(r)
         << dendl;

    m_instance_replayer.reset();
    m_ret_val = r;
    shut_down_local_status_updater();
    return;
  }

  for (auto kv_it : m_peers) {
    m_instance_replayer->add_peer({kv_it.second.uuid, kv_it.second.io_ctx,
                                   kv_it.second.status_updater});
  }

  init_instance_watcher();
}

template <typename I>
void NamespaceReplayer<I>::init_instance_watcher() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(!m_instance_watcher);

  m_instance_watcher.reset(InstanceWatcher<I>::create(
      m_local_io_ctx, *m_threads->asio_engine, m_instance_replayer.get(),
      m_image_sync_throttler));
  auto ctx = create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_init_instance_watcher>(this);

  m_instance_watcher->init(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_init_instance_watcher(int r) {
  dout(10) << "r=" << r << dendl;

  std::lock_guard locker{m_lock};

  if (r < 0) {
    derr << "error initializing instance watcher: " << cpp_strerror(r)
         << dendl;

    m_instance_watcher.reset();
    m_ret_val = r;
    shut_down_instance_replayer();
    return;
  }

  ceph_assert(m_on_finish != nullptr);
  m_threads->work_queue->queue(m_on_finish);
  m_on_finish = nullptr;
}

template <typename I>
void NamespaceReplayer<I>::stop_instance_replayer() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));

  Context *ctx = create_async_context_callback(
    m_threads->work_queue, create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_stop_instance_replayer>(this));

  m_instance_replayer->stop(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_stop_instance_replayer(int r) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error stopping instance replayer: " << cpp_strerror(r) << dendl;
  }

  std::lock_guard locker{m_lock};

  shut_down_instance_watcher();
}

template <typename I>
void NamespaceReplayer<I>::shut_down_instance_watcher() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(m_instance_watcher);

  Context *ctx = create_async_context_callback(
    m_threads->work_queue, create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_shut_down_instance_watcher>(this));

  m_instance_watcher->shut_down(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_instance_watcher(int r) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error shutting instance watcher down: " << cpp_strerror(r)
         << dendl;
  }

  std::lock_guard locker{m_lock};

  m_instance_watcher.reset();

  shut_down_instance_replayer();
}

template <typename I>
void NamespaceReplayer<I>::shut_down_instance_replayer() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(m_instance_replayer);

  Context *ctx = create_async_context_callback(
    m_threads->work_queue, create_context_callback<NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_shut_down_instance_replayer>(this));

  m_instance_replayer->shut_down(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_instance_replayer(int r) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error shutting instance replayer down: " << cpp_strerror(r)
         << dendl;
  }

  std::lock_guard locker{m_lock};

  m_instance_replayer.reset();
  shut_down_local_status_updater();
}

template <typename I>
void NamespaceReplayer<I>::shut_down_local_status_updater() {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(m_local_status_updater);

  auto ctx = create_async_context_callback(
    m_threads->work_queue, create_context_callback<
      NamespaceReplayer<I>,
      &NamespaceReplayer<I>::handle_shut_down_local_status_updater>(this));

  m_local_status_updater->shut_down(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_local_status_updater(int r) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error shutting local mirror status updater down: "
         << cpp_strerror(r) << dendl;
  }

  std::lock_guard locker{m_lock};

  m_local_status_updater.reset();

  ceph_assert(!m_image_map);
  ceph_assert(!m_image_deleter);
  ceph_assert(!m_local_pool_watcher);
  ceph_assert(!m_instance_watcher);
  ceph_assert(!m_instance_replayer);

  ceph_assert(m_on_finish != nullptr);
  m_threads->work_queue->queue(m_on_finish, m_ret_val);
  m_on_finish = nullptr;
  m_ret_val = 0;
}

template <typename I>
void NamespaceReplayer<I>::init_image_map(Context *on_finish) {
  dout(10) << dendl;

  auto image_map = ImageMap<I>::create(m_local_io_ctx, m_threads,
                                       m_instance_watcher->get_instance_id(),
                                       m_image_map_listener);

  auto ctx = new LambdaContext(
      [this, image_map, on_finish](int r) {
        handle_init_image_map(r, image_map, on_finish);
      });
  image_map->init(create_async_context_callback(
    m_threads->work_queue, ctx));
}

template <typename I>
void NamespaceReplayer<I>::handle_init_image_map(int r, ImageMap<I> *image_map,
                                                 Context *on_finish) {
  dout(10) << "r=" << r << dendl;
  if (r < 0) {
    derr << "failed to init image map: " << cpp_strerror(r) << dendl;
    on_finish = new LambdaContext([image_map, on_finish, r](int) {
        delete image_map;
        on_finish->complete(r);
      });
    image_map->shut_down(on_finish);
    return;
  }

  ceph_assert(!m_image_map);
  m_image_map.reset(image_map);

  init_local_pool_watcher(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::init_local_pool_watcher(Context *on_finish) {
  dout(10) << dendl;

  std::lock_guard locker{m_lock};
  ceph_assert(!m_local_pool_watcher);
  m_local_pool_watcher.reset(PoolWatcher<I>::create(
      m_threads, m_local_io_ctx, m_local_mirror_uuid,
      m_local_pool_watcher_listener));

  // ensure the initial set of local images is up-to-date
  // after acquiring the leader role
  auto ctx = new LambdaContext([this, on_finish](int r) {
      handle_init_local_pool_watcher(r, on_finish);
    });
  m_local_pool_watcher->init(create_async_context_callback(
    m_threads->work_queue, ctx));
}

template <typename I>
void NamespaceReplayer<I>::handle_init_local_pool_watcher(
    int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;
  if (r < 0) {
    derr << "failed to retrieve local images: " << cpp_strerror(r) << dendl;
    on_finish = new LambdaContext([on_finish, r](int) {
        on_finish->complete(r);
      });
    shut_down_local_pool_watcher(on_finish);
    return;
  }

  init_remote_pool_watchers(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::init_remote_pool_watchers(Context *on_finish) {
  dout(10) << dendl;
  std::lock_guard locker{m_lock};

  Context *ctx = new LambdaContext([this, on_finish](int r) {
    handle_init_remote_pool_watchers(r, on_finish);
  });
  ctx = create_async_context_callback(m_threads->work_queue, ctx);

  C_Gather *gather_ctx = new C_Gather(g_ceph_context, ctx);
  for (auto& kv : m_peers) {
    auto ctx = gather_ctx->new_sub();
    init_remote_pool_watcher(kv.second, ctx);
  }
  gather_ctx->activate();
}

template <typename I>
void NamespaceReplayer<I>::handle_init_remote_pool_watchers(
    int r, Context *on_finish) {
  dout(10) << dendl;

  if (r < 0) {
    derr << "failed to retrieve remote images: " << cpp_strerror(r) << dendl;
    on_finish = new LambdaContext([on_finish, r](int) {
      on_finish->complete(r);
    });
    return;
  }

  init_image_deleter(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::init_image_deleter(Context *on_finish) {
  dout(10) << dendl;

  std::lock_guard locker{m_lock};
  ceph_assert(!m_image_deleter);

  on_finish = new LambdaContext([this, on_finish](int r) {
      handle_init_image_deleter(r, on_finish);
    });
  m_image_deleter.reset(ImageDeleter<I>::create(m_local_io_ctx, m_threads,
                                                m_image_deletion_throttler,
                                                m_service_daemon));
  m_image_deleter->init(create_async_context_callback(
    m_threads->work_queue, on_finish));
}

template <typename I>
void NamespaceReplayer<I>::handle_init_image_deleter(
    int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;
  if (r < 0) {
    derr << "failed to init image deleter: " << cpp_strerror(r) << dendl;
    on_finish = new LambdaContext([on_finish, r](int) {
        on_finish->complete(r);
      });
    shut_down_image_deleter(on_finish);
    return;
  }

  on_finish->complete(0);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_image_deleter(Context* on_finish) {
  dout(10) << dendl;
  {
    std::lock_guard locker{m_lock};
    if (m_image_deleter) {
      Context *ctx = new LambdaContext([this, on_finish](int r) {
          handle_shut_down_image_deleter(r, on_finish);
	});
      ctx = create_async_context_callback(m_threads->work_queue, ctx);

      m_image_deleter->shut_down(ctx);
      return;
    }
  }
  shut_down_remote_pool_watchers(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_image_deleter(
    int r, Context* on_finish) {
  dout(10) << "r=" << r << dendl;

  {
    std::lock_guard locker{m_lock};
    ceph_assert(m_image_deleter);
    m_image_deleter.reset();
  }

  shut_down_remote_pool_watchers(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_remote_pool_watchers(
    Context* on_finish) {
  dout(10) << dendl;
  std::lock_guard locker{m_lock};

  Context *ctx = new LambdaContext([this, on_finish](int r) {
    handle_shut_down_remote_pool_watchers(r, on_finish);
  });
  ctx = create_async_context_callback(m_threads->work_queue, ctx);

  C_Gather *gather_ctx = new C_Gather(g_ceph_context, ctx);
  for (auto& kv : m_peers) {
    auto ctx = gather_ctx->new_sub();
    m_lock.unlock();
    shut_down_remote_pool_watcher(kv.second, ctx);
    m_lock.lock();
  }
  gather_ctx->activate();
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_remote_pool_watchers(
    int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;

  shut_down_local_pool_watcher(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_local_pool_watcher(Context *on_finish) {
  dout(10) << dendl;

  {
    std::lock_guard locker{m_lock};
    if (m_local_pool_watcher) {
      Context *ctx = new LambdaContext([this, on_finish](int r) {
          handle_shut_down_local_pool_watcher(r, on_finish);
	});
      ctx = create_async_context_callback(m_threads->work_queue, ctx);
      m_local_pool_watcher->shut_down(ctx);
      return;
    }
  }

  on_finish->complete(0);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_local_pool_watcher(
    int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;

  {
    std::lock_guard locker{m_lock};
    ceph_assert(m_local_pool_watcher);
    m_local_pool_watcher.reset();
  }
  shut_down_image_map(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_image_map(Context *on_finish) {
  dout(5) << dendl;

  std::lock_guard locker{m_lock};
  if (m_image_map) {
    on_finish = new LambdaContext(
        [this, on_finish](int r) {
          handle_shut_down_image_map(r, on_finish);
        });
    m_image_map->shut_down(create_async_context_callback(
        m_threads->work_queue, on_finish));
    return;
  }

  m_threads->work_queue->queue(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_image_map(int r, Context *on_finish) {
  dout(5) << "r=" << r << dendl;
  if (r < 0 && r != -EBLOCKLISTED) {
    derr << "failed to shut down image map: " << cpp_strerror(r) << dendl;
  }

  std::lock_guard locker{m_lock};
  ceph_assert(m_image_map);
  m_image_map.reset();

  m_instance_replayer->release_all(create_async_context_callback(
      m_threads->work_queue, on_finish));
}

template <typename I>
void NamespaceReplayer<I>::handle_acquire_image(const std::string &global_image_id,
                                           const std::string &instance_id,
                                           Context* on_finish) {
  dout(5) << "global_image_id=" << global_image_id << ", "
          << "instance_id=" << instance_id << dendl;

  m_instance_watcher->notify_image_acquire(instance_id, global_image_id,
                                           on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_release_image(const std::string &global_image_id,
                                           const std::string &instance_id,
                                           Context* on_finish) {
  dout(5) << "global_image_id=" << global_image_id << ", "
          << "instance_id=" << instance_id << dendl;

  m_instance_watcher->notify_image_release(instance_id, global_image_id,
                                           on_finish);
}

template <typename I>
void NamespaceReplayer<I>::handle_remove_image(const std::string &mirror_uuid,
                                          const std::string &global_image_id,
                                          const std::string &instance_id,
                                          Context* on_finish) {
  ceph_assert(!mirror_uuid.empty());
  dout(5) << "mirror_uuid=" << mirror_uuid << ", "
          << "global_image_id=" << global_image_id << ", "
          << "instance_id=" << instance_id << dendl;

  m_instance_watcher->notify_peer_image_removed(instance_id, global_image_id,
                                                mirror_uuid, on_finish);
}

template <typename I>
void NamespaceReplayer<I>::add_peer(const Peer<I>& peer, Context* on_finish) {
  dout(20) << "peer=" << peer << dendl;
  std::lock_guard locker{m_lock};

  ceph_assert(peer.status_updater == nullptr);
  ceph_assert(peer.pool_watcher == nullptr);

  auto result = m_peers.insert({peer.uuid, peer});
  ceph_assert(result.second);

  result.first->second.io_ctx.dup(peer.io_ctx);
  result.first->second.io_ctx.set_namespace(m_namespace_name);

  auto ctx = new LambdaContext([this, result, on_finish](int r) {
    if (m_instance_replayer) {
      m_instance_replayer->add_peer({result.first->second.uuid,
                                     result.first->second.io_ctx,
                                     result.first->second.status_updater});
    }
    m_threads->work_queue->queue(on_finish, r);
  });

  init_remote_status_updater(result.first->second, ctx);
}

template <typename I>
void NamespaceReplayer<I>::init_remote_status_updater(Peer<I>& peer,
                                                      Context* on_finish) {
  dout(10) << "peer=" << peer << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(peer.status_updater == nullptr);

  peer.status_updater = MirrorStatusUpdater<I>::create(
    peer.io_ctx, m_threads, m_local_mirror_uuid);
  auto ctx = new LambdaContext([this, &peer, on_finish](int r) {
    handle_init_remote_status_updater(peer, r, on_finish);
  });
  peer.status_updater->init(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_init_remote_status_updater(
    Peer<I>& peer, int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;

  std::lock_guard locker{m_lock};

  if (r < 0) {
    derr << "error initializing remote mirror status updater: "
         << cpp_strerror(r) << dendl;

    delete peer.status_updater;
    peer.status_updater = nullptr;
    on_finish->complete(r);
    return;
  }

  init_remote_pool_watcher(peer, on_finish);
}

template <typename I>
void NamespaceReplayer<I>::init_remote_pool_watcher(Peer<I>& peer,
                                                    Context *on_finish) {
  dout(10) << dendl;

  if (!m_image_map) {
    dout(10) << "not leader" << dendl;
    m_threads->work_queue->queue(on_finish);
    return;
  }

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(!peer.pool_watcher);
  RemotePoolMeta remote_pool_meta;
  ceph_assert(m_pool_meta_cache->get_remote_pool_meta(peer.io_ctx.get_id(),
    peer.uuid, &remote_pool_meta) == 0);
  peer.pool_watcher = PoolWatcher<I>::create(
      m_threads, peer.io_ctx, remote_pool_meta.mirror_uuid,
      m_remote_pool_watcher_listener);

  auto ctx = new LambdaContext([this, &peer, on_finish](int r) {
    handle_init_remote_pool_watcher(peer, r, on_finish);
  });
  peer.pool_watcher->init(create_async_context_callback(
    m_threads->work_queue, ctx));
}

template <typename I>
void NamespaceReplayer<I>::handle_init_remote_pool_watcher(
    Peer<I>& peer, int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;
  std::lock_guard locker{m_lock};

  if (r == -ENOENT) {
    // Technically nothing to do since the other side doesn't
    // have mirroring enabled. Eventually the remote pool watcher will
    // detect images (if mirroring is enabled), so no point propagating
    // an error which would just busy-spin the state machines.
    dout(0) << "remote peer does not have mirroring configured" << dendl;
  } else if (r < 0) {
    derr << "failed to retrieve remote images: " << cpp_strerror(r) << dendl;
    on_finish = new LambdaContext([on_finish, r](int) {
      on_finish->complete(r);
    });
    delete peer.pool_watcher;
    peer.pool_watcher = nullptr;
    shut_down_remote_status_updater(peer, on_finish);
    return;
  }

  m_threads->work_queue->queue(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_remote_status_updater(Peer<I>& peer,
                                                           Context *on_finish) {
  dout(10) << dendl;

  ceph_assert(ceph_mutex_is_locked(m_lock));
  ceph_assert(peer.status_updater);

  auto ctx = new LambdaContext([this, &peer, on_finish](int r) {
      handle_shut_down_remote_status_updater(peer, r, on_finish);
  });
  peer.status_updater->shut_down(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_remote_status_updater(
    Peer<I>& peer, int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error shutting remote mirror status updater down: "
         << cpp_strerror(r) << dendl;
  }

  std::lock_guard locker{m_lock};
  delete peer.status_updater;
  peer.status_updater = nullptr;

  m_threads->work_queue->queue(on_finish);
}

template <typename I>
void NamespaceReplayer<I>::remove_peer(const Peer<I>& peer,
                                       Context *on_finish) {
  dout(20) << "peer=" << peer << dendl;
  std::lock_guard locker{m_lock};
  auto peer_it = m_peers.find(peer.uuid);
  ceph_assert(peer_it != m_peers.end());

  Context* ctx = new LambdaContext([this, peer_it, on_finish](int r) {
    handle_remove_peer(peer_it->second, r, on_finish);
  });
  ctx = create_async_context_callback(m_threads->work_queue, ctx);
  if (m_instance_replayer) {
    m_instance_replayer->remove_peer({peer_it->second.uuid,
                                      peer_it->second.io_ctx,
                                      peer_it->second.status_updater}, ctx);
    return;
  }
  m_threads->work_queue->queue(ctx, 0);
}

template <typename I>
void NamespaceReplayer<I>::handle_remove_peer(const Peer<I>& peer, int r,
                                              Context *on_finish) {
  dout(10) << "peer=" << peer << dendl;
  std::lock_guard locker{m_lock};
  auto peer_it = m_peers.find(peer.uuid);
  ceph_assert(peer_it != m_peers.end());
  Context* ctx = new LambdaContext([this, peer_it, on_finish](int r) {
    std::lock_guard locker{m_lock};
    auto size = m_peers.size();
    m_peers.erase(peer_it);
    ceph_assert(size != m_peers.size());
    m_threads->work_queue->queue(on_finish, r);
  });
  ctx = new LambdaContext([this, peer_it, ctx](int r) {
    if (m_image_map) {
      shut_down_remote_pool_watcher(peer_it->second, ctx);
      return;
    }
    ctx->complete(r);
  });

  shut_down_remote_status_updater(peer_it->second, ctx);
}

template <typename I>
void NamespaceReplayer<I>::shut_down_remote_pool_watcher(
    Peer<I>& peer, Context *on_finish) {
  dout(10) << dendl;

  std::lock_guard locker{m_lock};
  ceph_assert(peer.pool_watcher);

  Context* ctx = new LambdaContext([this, &peer, on_finish](int r) {
    handle_shut_down_remote_pool_watcher(peer, r, on_finish);
  });
  ctx = create_async_context_callback(m_threads->work_queue, ctx);
  peer.pool_watcher->shut_down(ctx);
}

template <typename I>
void NamespaceReplayer<I>::handle_shut_down_remote_pool_watcher(
    Peer<I>& peer, int r, Context *on_finish) {
  dout(10) << "r=" << r << dendl;

  if (r < 0) {
    derr << "error shutting remote mirror pool watcher down: "
         << cpp_strerror(r) << dendl;
  }

  std::lock_guard locker{m_lock};
  delete peer.pool_watcher;
  peer.pool_watcher = nullptr;

  m_threads->work_queue->queue(on_finish, r);
}

} // namespace mirror
} // namespace rbd

template class rbd::mirror::NamespaceReplayer<librbd::ImageCtx>;
