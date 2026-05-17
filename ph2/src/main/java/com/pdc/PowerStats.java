package com.pdc;

import org.apache.hadoop.io.Writable;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;

// {sum, count, min, max} aggregator. Used as both mapper output value and
// reducer output value, so it implements Writable for shuffle serialization.
public final class PowerStats implements Writable {

    public double sum;
    public long   count;
    public double min;
    public double max;

    public PowerStats() {
        reset();
    }

    public void reset() {
        sum   = 0.0;
        count = 0L;
        min   = Double.POSITIVE_INFINITY;
        max   = Double.NEGATIVE_INFINITY;
    }

    public void observe(double v) {
        sum   += v;
        count += 1L;
        if (v < min) min = v;
        if (v > max) max = v;
    }

    public void merge(PowerStats other) {
        sum   += other.sum;
        count += other.count;
        if (other.min < min) min = other.min;
        if (other.max > max) max = other.max;
    }

    public double mean() {
        return count == 0 ? Double.NaN : sum / (double) count;
    }

    @Override
    public void write(DataOutput out) throws IOException {
        out.writeDouble(sum);
        out.writeLong(count);
        out.writeDouble(min);
        out.writeDouble(max);
    }

    @Override
    public void readFields(DataInput in) throws IOException {
        sum   = in.readDouble();
        count = in.readLong();
        min   = in.readDouble();
        max   = in.readDouble();
    }

    @Override
    public String toString() {
        // Tab-separated for human-readable HDFS part-r-* files.
        return String.format("sum=%.6f\tcount=%d\tmin=%.6f\tmax=%.6f",
                             sum, count, min, max);
    }
}
