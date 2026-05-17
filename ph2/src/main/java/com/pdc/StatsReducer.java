package com.pdc;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.mapreduce.Reducer;

import java.io.IOException;

// Used both as combiner (mapper-side merge) and reducer (final merge per key).
// Idempotent under merge(), so wiring it twice is safe.
public final class StatsReducer
        extends Reducer<IntWritable, PowerStats, IntWritable, PowerStats> {

    private final PowerStats agg = new PowerStats();

    @Override
    protected void reduce(IntWritable bucket,
                          Iterable<PowerStats> values,
                          Context ctx)
            throws IOException, InterruptedException {
        agg.reset();
        for (PowerStats v : values) {
            agg.merge(v);
        }
        ctx.write(bucket, agg);
    }
}
