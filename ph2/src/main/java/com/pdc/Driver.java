package com.pdc;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.SequenceFile;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.SequenceFileOutputFormat;
import org.apache.hadoop.util.Tool;
import org.apache.hadoop.util.ToolRunner;

// Submits the MR job, then reads the K part-r-* files from HDFS and merges
// them client-side. Final stats also written to /output/final/stats.txt.
//
// Args: --input <hdfs path> --output <hdfs path> --reduces <N> [--final <hdfs path>]
// Hadoop generic options (-D key=value, -conf, etc.) are consumed by ToolRunner
// before our args parser sees them.
public final class Driver extends Configured implements Tool {

    public static void main(String[] args) throws Exception {
        int rc = ToolRunner.run(new Configuration(), new Driver(), args);
        System.exit(rc);
    }

    @Override
    public int run(String[] args) throws Exception {
        String input  = "/input/data.txt";
        String output = "/output/run";
        int    nReduces = 1;
        String finalOut = "/output/final/stats.txt";

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--input":   input    = args[++i]; break;
                case "--output":  output   = args[++i]; break;
                case "--reduces": nReduces = Integer.parseInt(args[++i]); break;
                case "--final":   finalOut = args[++i]; break;
                default:
                    System.err.println("unknown arg: " + args[i]);
                    return 2;
            }
        }

        Configuration conf = getConf();
        FileSystem fs = FileSystem.get(conf);

        // Wipe output dir if present, so each run is fresh.
        Path outPath = new Path(output);
        if (fs.exists(outPath)) {
            fs.delete(outPath, true);
        }

        Job job = Job.getInstance(conf, "ph2-power-stats");
        job.setJarByClass(Driver.class);

        job.setMapperClass(StatsMapper.class);
        job.setCombinerClass(StatsReducer.class);
        job.setReducerClass(StatsReducer.class);

        job.setMapOutputKeyClass(IntWritable.class);
        job.setMapOutputValueClass(PowerStats.class);
        job.setOutputKeyClass(IntWritable.class);
        job.setOutputValueClass(PowerStats.class);

        // Sequence file output so we can rehydrate PowerStats client-side.
        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(SequenceFileOutputFormat.class);

        job.setNumReduceTasks(nReduces);

        FileInputFormat.addInputPath(job, new Path(input));
        FileOutputFormat.setOutputPath(job, outPath);

        long t0 = System.nanoTime();
        boolean ok = job.waitForCompletion(true);
        if (!ok) {
            System.err.println("job failed");
            return 1;
        }

        // Merge the K per-reducer partials into one final aggregate.
        PowerStats finalStats = new PowerStats();
        FileStatus[] parts = fs.listStatus(outPath, p -> p.getName().startsWith("part-r-"));
        for (FileStatus st : parts) {
            try (SequenceFile.Reader r = new SequenceFile.Reader(conf,
                    SequenceFile.Reader.file(st.getPath()))) {
                IntWritable k = new IntWritable();
                PowerStats  v = new PowerStats();
                while (r.next(k, v)) {
                    finalStats.merge(v);
                }
            }
        }
        long t1 = System.nanoTime();
        double elapsedMs = (t1 - t0) / 1.0e6;

        // Phase 1 binary parity: identical stdout shape, easy to diff.
        System.out.printf("[mr] input=%s reduces=%d%n", input, nReduces);
        System.out.printf("[mr] n=%d  avg=%.9f  min=%.9f  max=%.9f%n",
                finalStats.count, finalStats.mean(), finalStats.min, finalStats.max);
        System.out.printf("[mr] elapsed_ms=%.3f%n", elapsedMs);

        // Persist final result back into HDFS so we tick the
        // "Generate the final result in HDFS" requirement.
        Path finalPath = new Path(finalOut);
        Path parent = finalPath.getParent();
        if (parent != null && !fs.exists(parent)) fs.mkdirs(parent);
        try (FSDataOutputStream out = fs.create(finalPath, true);
             java.io.PrintWriter pw = new java.io.PrintWriter(
                     new java.io.OutputStreamWriter(out, "UTF-8"))) {
            pw.printf("n=%d avg=%.9f min=%.9f max=%.9f reduces=%d elapsed_ms=%.3f%n",
                    finalStats.count, finalStats.mean(), finalStats.min, finalStats.max,
                    nReduces, elapsedMs);
        }
        System.out.printf("[mr] wrote final stats to hdfs://%s%n", finalOut);
        return 0;
    }
}
