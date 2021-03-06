import bio.bam.pileup;
import bio.bam.reader;
import std.algorithm: filter, map;
import std.array: split;
import std.conv: to;
import std.file: exists;
import std.format;
import std.getopt;
import std.range;
import std.stdio;

static string usage = "ac - alleleCounter clone\nUsage: ac -b|--bamfile <bamfile> -l|--locifile <locifile>\n       ac -h|--help";

int ref_id(R)(R reader, string ref_name) {
    return reader[ref_name].id;
}

auto count_bases(string bases) {
    int nA, nC, nG, nT;
    foreach(base; bases) {
        switch(base) {
            case 'A': nA++; break;
            case 'C': nC++; break;
            case 'G': nG++; break;
            case 'T': nT++; break;
            default: break;
        }
    }
    auto s = format!"%d\t%d\t%d\t%d\t%d"(nA, nC, nG, nT, nA+nC+nG+nT);
    return s;
}

auto qual_to_ascii(Array)(Array qualities) {
    map!(v => v+33).array();
}

void main(string[] argv)
{
    string bamfile;
    string locifile;
    int minmapqual = 35;
    int minbasequal = 20;

    try {
        auto args = getopt(
                argv,
                std.getopt.config.required, "bamfile|b", "Path to sample BAM file.", &bamfile,
                std.getopt.config.required, "locifile|l", "Path to loci file.", &locifile,
                "minbasequal|m", "Minimum base quality [Default: 20].", &minbasequal,
                "minmapqual|q", "Minimum mapping quality [Default: 35].", &minmapqual);

        if (args.helpWanted) {
            defaultGetoptPrinter(usage, args.options);
            return;
        }
    }
    catch (GetOptException) {
        writeln(usage);
        return;
    }

    if(!exists(bamfile)) {
        writefln("File %s does not exist: exiting.", bamfile);
        return;
    }

    if(!exists(locifile)) {
        writefln("File %s does not exist: exiting.", locifile);
        return;
    }

    auto bam = new BamReader(bamfile);
    auto loci = File(locifile);
    scope(exit) {
        loci.close();
    }

    if (!bam.has_index()) {
        bam.createIndex();
    }

    int curr_ref = 0;
    auto pileup = makePileup(bam.reference(curr_ref)[1 .. uint.max]);
    auto column = pileup.front;

    writefln("#CHR\tPOS\tCount_A\tCount_C\tCount_G\tCount_T\tGood_depth");

    foreach (line; loci.byLineCopy) {
        auto spl = split(line, '\t');
        string refname = to!string(spl[0]);
        auto ref_id = bam.ref_id(refname);
        ulong pos_1based = to!ulong(spl[1]);
        auto pos_0based = pos_1based - 1;

        if (ref_id != curr_ref) {
            curr_ref = ref_id;
            pileup = makePileup(bam.reference(curr_ref)[1 .. uint.max]);
            column = pileup.front;
        }

        if (pileup.empty) {
            writefln("%s\t%d\t0\t0\t0\t0\t0", refname, pos_1based);
            continue;
        }

        assert(column.ref_id == ref_id);
        while(column.position < pos_0based && column.ref_id == ref_id) {
            if (pileup.empty) {
                writefln("%s\t%d\t0\t0\t0\t0\t0", refname, pos_1based);
                break;
            }
            pileup.popFront();
            column = pileup.front;
        }

        if (column.position == pos_0based) {
            auto bases = column.reads
                .filter!(read => (read.current_base_quality >= minbasequal) && (read.mapping_quality >= minmapqual) && !read.is_duplicate())
                .map!(read => read.current_base)
                .to!string;
            writefln("%s\t%d\t%s", refname, pos_1based, count_bases(bases));
        }

        if (column.position > pos_0based) {
            writefln("%s\t%d\t0\t0\t0\t0\t0", refname, pos_1based);
            continue;
        }
    }
}

