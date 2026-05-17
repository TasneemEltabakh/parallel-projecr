package com.pdc;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

import java.io.IOException;

// Bucket every value into one of NUM_BUCKETS keys. The bucket count is
// chosen larger than the largest reducer count in the benchmark sweep
// (8) so 1/2/4/8 reducers all get real work to do instead of a single
// key piling onto one reducer.
public final class StatsMapper
        extends Mapper<LongWritable, Text, IntWritable, PowerStats> {

    public static final int NUM_BUCKETS = 16;

    private final IntWritable   bucketKey = new IntWritable();
    private final PowerStats    one       = new PowerStats();
    private long                lineNo    = 0L;

    @Override
    protected void map(LongWritable offset, Text line, Context ctx)
            throws IOException, InterruptedException {
        String s = line.toString().trim();
        if (s.isEmpty()) return;
        double v;
        try {
            v = Double.parseDouble(s);
        } catch (NumberFormatException ex) {
            ctx.getCounter("stats", "parse_failures").increment(1L);
            return;
        }
        one.reset();
        one.observe(v);
        bucketKey.set((int) (lineNo++ % NUM_BUCKETS));
        ctx.write(bucketKey, one);
    }
}
