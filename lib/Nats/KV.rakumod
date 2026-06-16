use JSON::Fast;

# ═════════════════════════════════════════════
# NATS JetStream Key-Value Store
# ═════════════════════════════════════════════
#
# Built on top of JetStream streams. Each KV bucket is a stream
# with max_msgs_per_subject=1 (last-write-wins) and discard=new.
#
# API subjects: $KV.<bucket>.<key>
#
# Usage:
#   my $kv = $nats.kv('mybucket');
#   await $kv.create;
#   $kv.put('foo', 'bar');
#   say $kv.get('foo');  # bar
#   $kv.delete('foo');

class Nats::KV {
    has $.nats is required;
    has Str $.bucket is required;
    has Str $.description;
    has Int $.max-age = 0;        # 0 = no TTL
    has $.stream;

    # Full subject prefix for this bucket
    method prefix { "\$KV.{ $!bucket }" }

    # Build a stream object configured as a KV bucket
    method !build-stream {
        Nats::Stream.new:
            :$!nats,
            :name("KV_{ $!bucket }"),
            :subjects(["{ self.prefix }.>"]),
            :retention<limits>,
            :discard<new>,
            :max-msgs-per-subject(1),
            :allow-direct,
            :max-age($!max-age),
            |($!description ?? :$!description !! Empty),
    }

    # Create the KV bucket (idempotent — existing buckets are reused)
    method create {
        $!stream = self!build-stream;
        $!stream.create;
    }

    # Get stream info
    method info {
        $!stream.info;
    }

    # Delete the entire bucket
    method destroy {
        $!stream.delete;
    }

    # ── CRUD operations ──

    # Put a value for a key
    method put(Str $key, Str() $value) {
        $!nats.publish: "{ self.prefix }.{ $key }", $value;
    }

    # Get the current value for a key (returns Str or Nil)
    method get(Str $key --> Str) {
        my $resp = $!stream.get-last-msg("{ self.prefix }.{ $key }");
        return Nil without $resp;
        my $msg = await $resp.Promise;
        return Nil unless $msg && $msg.payload && $msg.payload.chars > 0;
        $msg.payload;
    }

    # Delete a key (publishes a tombstone — empty payload)
    method delete(Str $key) {
        $!nats.publish: "{ self.prefix }.{ $key }", "";
    }

    # ── Bulk operations ──

    # List all keys in the bucket
    method keys(--> Seq) {
        my $resp = $!stream.info;
        return ().Seq without $resp;
        my $msg = await $resp.Promise;
        return ().Seq unless $msg && $msg.payload;
        my %info = try from-json($msg.payload);
        return ().Seq if $!;
        my $prefix = "{ self.prefix }.";
        my $len    = $prefix.chars;
        gather {
            for %info<state><subjects>.List -> $subject {
                next unless $subject.starts-with($prefix);
                take $subject.substr($len);
            }
        }
    }

    # ── Watcher ──

    # Subscribe to all changes in the bucket.
    # Returns a Nats::Subscription. Use $sub.supply to react.
    method watch {
        $!nats.subscribe: "{ self.prefix }.>";
    }

    # ── History ──

    # Get the history of a key (requires the stream to have max_msgs_per_subject > 1).
    # Not supported in this implementation (KV buckets use max_msgs_per_subject=1).
    method history(Str $key) {
        die "history() requires max-msgs-per-subject > 1. This KV bucket uses the default (1).";
    }
}
