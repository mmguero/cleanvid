#!/usr/bin/env python3

import argparse
import base64
import chardet
import codecs
import errno
import json
import os
import shutil
import sys
import re
import pysrt
import delegator
from subliminal import *
from babelfish import Language

try:
    from cleanvid.caselessdictionary import CaselessDictionary
except ImportError:
    from caselessdictionary import CaselessDictionary
from itertools import tee

__script_location__ = os.path.dirname(os.path.realpath(__file__))

VIDEO_DEFAULT_PARAMS = '-c:v libx264 -preset slow -crf 22'
AUDIO_DEFAULT_PARAMS = '-c:a aac -ac 2 -ab 224k -ar 44100'
SUBTITLE_DEFAULT_LANG = 'eng'
PLEX_AUTO_SKIP_DEFAULT_CONFIG = '{"markers":{},"offsets":{},"tags":{},"allowed":{"users":[],"clients":[],"keys":[]},"blocked":{"users":[],"clients":[],"keys":[]},"clients":{},"mode":{}}'

# thanks https://docs.python.org/3/library/itertools.html#recipes
def pairwise(iterable):
    a, b = tee(iterable)
    next(b, None)
    return zip(a, b)


######## GetFormatAndStreamInfo ###############################################
def GetFormatAndStreamInfo(vidFileSpec):
    result = None
    if os.path.isfile(vidFileSpec):
        ffprobeCmd = "ffprobe -v quiet -print_format json -show_format -show_streams \"" + vidFileSpec + "\""
        ffprobeResult = delegator.run(ffprobeCmd, block=True)
        if ffprobeResult.return_code == 0:
            result = json.loads(ffprobeResult.out)
    return result


######## ExtractSubtitles #####################################################
def ExtractSubtitles(vidFileSpec, srtLanguage):
    subFileSpec = ""
    if (
        (streamInfo := GetFormatAndStreamInfo(vidFileSpec))
        and ('streams' in streamInfo)
        and (len(streamInfo['streams']) > 0)
        and (
            streams := [
                x
                for x in streamInfo['streams']
                if ('codec_type' in x)
                and ('index' in x)
                and (x['codec_type'] == 'subtitle')
                and ('codec_name' in x)
                and (x['codec_name'] == 'subrip')
                and ('tags' in x)
                and ('language' in x['tags'])
                and (x['tags']['language'] == srtLanguage)
            ]
        )
    ):
        subFileParts = os.path.splitext(vidFileSpec)
        subFileSpec = subFileParts[0] + "." + srtLanguage + ".srt"
        ffmpegCmd = "ffmpeg -y -i \"" + vidFileSpec + f"\" -map 0:{streams[0]['index']} \"" + subFileSpec + "\""
        ffmpegResult = delegator.run(ffmpegCmd, block=True)
        if (ffmpegResult.return_code != 0) or (not os.path.isfile(subFileSpec)):
            subFileSpec = ""
    return subFileSpec


######## GetSubtitles #########################################################
def GetSubtitles(vidFileSpec, srtLanguage, offline=False):
    subFileSpec = ExtractSubtitles(vidFileSpec, srtLanguage)
    if not os.path.isfile(subFileSpec):
        if offline:
            subFileSpec = ""
        else:
            if os.path.isfile(vidFileSpec):
                subFileParts = os.path.splitext(vidFileSpec)
                subFileSpec = subFileParts[0] + "." + str(Language(srtLanguage)) + ".srt"
                if not os.path.isfile(subFileSpec):
                    video = Video.fromname(vidFileSpec)
                    bestSubtitles = download_best_subtitles([video], {Language(srtLanguage)})
                    savedSub = save_subtitles(video, [bestSubtitles[video][0]])

            if subFileSpec and (not os.path.isfile(subFileSpec)):
                subFileSpec = ""

    return subFileSpec


######## UTF8Convert #########################################################
# attempt to convert any text file to UTF-* without BOM and normalize line endings
def UTF8Convert(fileSpec, universalEndline=True):

    # Read from file
    with open(fileSpec, 'rb') as f:
        raw = f.read()

    # Decode
    raw = raw.decode(chardet.detect(raw)['encoding'])

    # Remove windows line endings
    if universalEndline:
        raw = raw.replace('\r\n', '\n')

    # Encode to UTF-8
    raw = raw.encode('utf8')

    # Remove BOM
    if raw.startswith(codecs.BOM_UTF8):
        raw = raw.replace(codecs.BOM_UTF8, '', 1)

    # Write to file
    with open(fileSpec, 'wb') as f:
        f.write(raw)


#################################################################################
class VidCleaner(object):
    inputVidFileSpec = ""
    inputSubsFileSpec = ""
    cleanSubsFileSpec = ""
    edlFileSpec = ""
    tmpSubsFileSpec = ""
    assSubsFileSpec = ""
    outputVidFileSpec = ""
    swearsFileSpec = ""
    swearsPadMillisec = 0
    embedSubs = False
    fullSubs = False
    subsOnly = False
    edl = False
    hardCode = False
    reEncode = False
    unalteredVideo = False
    subsLang = SUBTITLE_DEFAULT_LANG
    vParams = VIDEO_DEFAULT_PARAMS
    aParams = AUDIO_DEFAULT_PARAMS
    plexAutoSkipJson = ""
    plexAutoSkipId = ""
    swearsMap = CaselessDictionary({})
    muteTimeList = []

    ######## init #################################################################

    def __init__(
        self,
        iVidFileSpec,
        iSubsFileSpec,
        oVidFileSpec,
        oSubsFileSpec,
        iSwearsFileSpec,
        swearsPadSec=0,
        embedSubs=False,
        fullSubs=False,
        subsOnly=False,
        edl=False,
        subsLang=SUBTITLE_DEFAULT_LANG,
        reEncode=False,
        hardCode=False,
        vParams=VIDEO_DEFAULT_PARAMS,
        aParams=AUDIO_DEFAULT_PARAMS,
        plexAutoSkipJson="",
        plexAutoSkipId="",
    ):

        if (iVidFileSpec is not None) and os.path.isfile(iVidFileSpec):
            self.inputVidFileSpec = iVidFileSpec
        else:
            raise IOError(errno.ENOENT, os.strerror(errno.ENOENT), iVidFileSpec)

        if (iSubsFileSpec is not None) and os.path.isfile(iSubsFileSpec):
            self.inputSubsFileSpec = iSubsFileSpec

        if (iSwearsFileSpec is not None) and os.path.isfile(iSwearsFileSpec):
            self.swearsFileSpec = iSwearsFileSpec
        else:
            raise IOError(errno.ENOENT, os.strerror(errno.ENOENT), iSwearsFileSpec)

        if (oVidFileSpec is not None) and (len(oVidFileSpec) > 0):
            self.outputVidFileSpec = oVidFileSpec
            if os.path.isfile(self.outputVidFileSpec):
                os.remove(self.outputVidFileSpec)

        if (oSubsFileSpec is not None) and (len(oSubsFileSpec) > 0):
            self.cleanSubsFileSpec = oSubsFileSpec
            if os.path.isfile(self.cleanSubsFileSpec):
                os.remove(self.cleanSubsFileSpec)

        self.swearsPadMillisec = swearsPadSec * 1000
        self.embedSubs = embedSubs
        self.fullSubs = fullSubs
        self.subsOnly = subsOnly or edl or (plexAutoSkipJson and plexAutoSkipId)
        self.edl = edl
        self.plexAutoSkipJson = plexAutoSkipJson
        self.plexAutoSkipId = plexAutoSkipId
        self.reEncode = reEncode
        self.hardCode = hardCode
        self.subsLang = subsLang
        self.vParams = vParams
        self.aParams = aParams
        if self.vParams.startswith('base64:'):
            self.vParams = base64.b64decode(self.vParams[7:]).decode('utf-8')
        if self.aParams.startswith('base64:'):
            self.aParams = base64.b64decode(self.aParams[7:]).decode('utf-8')

    ######## del ##################################################################
    def __del__(self):
        if (not os.path.isfile(self.outputVidFileSpec)) and (not self.unalteredVideo):
            if os.path.isfile(self.cleanSubsFileSpec):
                os.remove(self.cleanSubsFileSpec)
            if os.path.isfile(self.edlFileSpec):
                os.remove(self.edlFileSpec)
        if os.path.isfile(self.tmpSubsFileSpec):
            os.remove(self.tmpSubsFileSpec)
        if os.path.isfile(self.assSubsFileSpec):
            os.remove(self.assSubsFileSpec)

    ######## CreateCleanSubAndMuteList #################################################
    def CreateCleanSubAndMuteList(self):
        if (self.inputSubsFileSpec is None) or (not os.path.isfile(self.inputSubsFileSpec)):
            raise IOError(
                errno.ENOENT,
                f"Input subtitle file unspecified or not found ({os.strerror(errno.ENOENT)})",
                self.inputSubsFileSpec,
            )

        subFileParts = os.path.splitext(self.inputSubsFileSpec)

        self.tmpSubsFileSpec = subFileParts[0] + "_utf8" + subFileParts[1]
        shutil.copy2(self.inputSubsFileSpec, self.tmpSubsFileSpec)
        UTF8Convert(self.tmpSubsFileSpec)

        if not self.cleanSubsFileSpec:
            self.cleanSubsFileSpec = subFileParts[0] + "_clean" + subFileParts[1]

        if not self.edlFileSpec:
            cleanSubFileParts = os.path.splitext(self.cleanSubsFileSpec)
            self.edlFileSpec = cleanSubFileParts[0] + '.edl'

        lines = []

        with open(self.swearsFileSpec) as f:
            lines = [line.rstrip('\n') for line in f]

        for line in lines:
            lineMap = line.split("|")
            if len(lineMap) > 1:
                self.swearsMap[lineMap[0]] = lineMap[1]
            else:
                self.swearsMap[lineMap[0]] = "*****"

        replacer = re.compile(r'\b(' + '|'.join(self.swearsMap.keys()) + r')\b', re.IGNORECASE)

        subs = pysrt.open(self.tmpSubsFileSpec)
        newSubs = pysrt.SubRipFile()
        newTimestampPairs = []

        # for each subtitle in the set
        # if text contains profanity...
        # OR if the next text contains profanity and lies within the pad ...
        # OR if the previous text contained profanity and lies within the pad ...
        # then include the subtitle in the new set
        prevNaughtySub = None
        for sub, subPeek in pairwise(subs):
            newText = replacer.sub(lambda x: self.swearsMap[x.group()], sub.text)
            newTextPeek = (
                replacer.sub(lambda x: self.swearsMap[x.group()], subPeek.text) if (subPeek is not None) else None
            )
            # this sub contains profanity, or
            if (
                (newText != sub.text)
                or
                # we have defined a pad, and
                (
                    (self.swearsPadMillisec > 0)
                    and (newTextPeek is not None)
                    and
                    # the next sub contains profanity and is within pad seconds of this one, or
                    (
                        (
                            (newTextPeek != subPeek.text)
                            and ((subPeek.start.ordinal - sub.end.ordinal) <= self.swearsPadMillisec)
                        )
                        or
                        # the previous sub contained profanity and is within pad seconds of this one
                        (
                            (prevNaughtySub is not None)
                            and ((sub.start.ordinal - prevNaughtySub.end.ordinal) <= self.swearsPadMillisec)
                        )
                    )
                )
            ):
                subScrubbed = newText != sub.text
                newSub = sub
                newSub.text = newText
                newSubs.append(newSub)
                if subScrubbed:
                    prevNaughtySub = sub
                    newTimes = [
                        pysrt.SubRipTime.from_ordinal(sub.start.ordinal - self.swearsPadMillisec).to_time(),
                        pysrt.SubRipTime.from_ordinal(sub.end.ordinal + self.swearsPadMillisec).to_time(),
                    ]
                else:
                    prevNaughtySub = None
                    newTimes = [sub.start.to_time(), sub.end.to_time()]
                newTimestampPairs.append(newTimes)
            else:
                if self.fullSubs:
                    newSubs.append(sub)
                prevNaughtySub = None

        newSubs.save(self.cleanSubsFileSpec)

        self.muteTimeList = []
        edlLines = []
        plexDict = json.loads(PLEX_AUTO_SKIP_DEFAULT_CONFIG) if self.plexAutoSkipId and self.plexAutoSkipJson else None

        if plexDict:
            plexDict["markers"][self.plexAutoSkipId] = []
            plexDict["mode"][self.plexAutoSkipId] = "volume"

        for timePair in newTimestampPairs:
            lineStart = (
                (timePair[0].hour * 60.0 * 60.0)
                + (timePair[0].minute * 60.0)
                + timePair[0].second
                + (timePair[0].microsecond / 1000000.0)
            )
            lineEnd = (
                (timePair[1].hour * 60.0 * 60.0)
                + (timePair[1].minute * 60.0)
                + timePair[1].second
                + (timePair[1].microsecond / 1000000.0)
            )
            self.muteTimeList.append(
                "volume=enable='between(t," + format(lineStart, '.3f') + "," + format(lineEnd, '.3f') + ")':volume=0"
            )
            if self.edl:
                edlLines.append(f"{format(lineStart, '.1f')}\t{format(lineEnd, '.3f')}\t1")
            if plexDict:
                plexDict["markers"][self.plexAutoSkipId].append(
                    {"start": round(lineStart * 1000.0), "end": round(lineEnd * 1000.0), "mode": "volume"}
                )
        if self.edl and (len(edlLines) > 0):
            with open(self.edlFileSpec, 'w') as edlFile:
                for item in edlLines:
                    edlFile.write(f"{item}\n")
        if plexDict and (len(plexDict["markers"][self.plexAutoSkipId]) > 0):
            json.dump(
                plexDict,
                open(self.plexAutoSkipJson, 'w'),
                indent=4,
            )

    ######## MultiplexCleanVideo ###################################################
    def MultiplexCleanVideo(self):

        # if we're don't *have* to generate a new video file, don't
        # we need to generate a video file if any of the following are true:
        # - we were explicitly asked to re-encode
        # - we are hard-coding (burning) subs
        # - we are embedding a subtitle stream
        # - we are not doing "subs only" or EDL mode and there more than zero mute sections
        if self.reEncode or self.hardCode or self.embedSubs or ((not self.subsOnly) and (len(self.muteTimeList) > 0)):
            if self.reEncode or self.hardCode:
                if self.hardCode and os.path.isfile(self.cleanSubsFileSpec):
                    self.assSubsFileSpec = self.cleanSubsFileSpec + '.ass'
                    subConvCmd = f"ffmpeg -y -i {self.cleanSubsFileSpec} {self.assSubsFileSpec}"
                    subConvResult = delegator.run(subConvCmd, block=True)
                    if (subConvResult.return_code == 0) and os.path.isfile(self.assSubsFileSpec):
                        videoArgs = f"{self.vParams} -vf \"ass={self.assSubsFileSpec}\""
                    else:
                        print(subConvCmd)
                        print(subConvResult.err)
                        raise ValueError(f'Could not process {self.cleanSubsFileSpec}')
                else:
                    videoArgs = self.vParams
            else:
                videoArgs = "-c:v copy"
            if (not self.subsOnly) and (len(self.muteTimeList) > 0):
                audioArgs = " -af \"" + ",".join(self.muteTimeList) + "\" "
            else:
                audioArgs = " "
            if self.embedSubs and os.path.isfile(self.cleanSubsFileSpec):
                outFileParts = os.path.splitext(self.outputVidFileSpec)
                subsArgs = f" -i \"{self.cleanSubsFileSpec}\" -map 0 -map -0:s -map 1 -c:s {'mov_text' if outFileParts[1] == '.mp4' else 'srt'} -disposition:s:0 default -metadata:s:s:0 language={self.subsLang} "
            else:
                subsArgs = " -sn "
            ffmpegCmd = (
                "ffmpeg -y -i \""
                + self.inputVidFileSpec
                + "\""
                + subsArgs
                + videoArgs
                + audioArgs
                + f"{self.aParams} \""
                + self.outputVidFileSpec
                + "\""
            )
            ffmpegResult = delegator.run(ffmpegCmd, block=True)
            if (ffmpegResult.return_code != 0) or (not os.path.isfile(self.outputVidFileSpec)):
                print(ffmpegCmd)
                print(ffmpegResult.err)
                raise ValueError(f'Could not process {self.inputVidFileSpec}')
        else:
            self.unalteredVideo = True


#################################################################################
def RunCleanvid():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-s',
        '--subs',
        help='.srt subtitle file (will attempt auto-download if unspecified and not --offline)',
        metavar='<srt>',
    )
    parser.add_argument('-i', '--input', required=True, help='input video file', metavar='<input video>')
    parser.add_argument('-o', '--output', help='output video file', metavar='<output video>')
    parser.add_argument(
        '--plex-auto-skip-json',
        help='custom JSON file for PlexAutoSkip (also implies --subs-only)',
        metavar='<output JSON>',
        dest="plexAutoSkipJson",
    )
    parser.add_argument(
        '--plex-auto-skip-id',
        help='content identifier for PlexAutoSkip (also implies --subs-only)',
        metavar='<content identifier>',
        dest="plexAutoSkipId",
    )
    parser.add_argument('--subs-output', help='output subtitle file', metavar='<output srt>', dest="subsOut")
    parser.add_argument(
        '-w',
        '--swears',
        help='text file containing profanity (with optional mapping)',
        default=os.path.join(__script_location__, 'swears.txt'),
        metavar='<profanity file>',
    )
    parser.add_argument(
        '-l',
        '--lang',
        help=f'language for srt download (default is "{SUBTITLE_DEFAULT_LANG}")',
        default=SUBTITLE_DEFAULT_LANG,
        metavar='<language>',
    )
    parser.add_argument(
        '-p', '--pad', help='pad (seconds) around profanity', metavar='<int>', dest="pad", type=int, default=0
    )
    parser.add_argument(
        '-e',
        '--embed-subs',
        help='embed subtitles in resulting video file',
        dest='embedSubs',
        action='store_true',
    )
    parser.add_argument(
        '-f',
        '--full-subs',
        help='include all subtitles in output subtitle file (not just scrubbed)',
        dest='fullSubs',
        action='store_true',
    )
    parser.add_argument(
        '--subs-only',
        help='only operate on subtitles (do not alter audio)',
        dest='subsOnly',
        action='store_true',
    )
    parser.add_argument(
        '--offline',
        help="don't attempt to download subtitles",
        dest='offline',
        action='store_true',
    )
    parser.add_argument(
        '--edl',
        help='generate MPlayer EDL file with mute actions (also implies --subs-only)',
        dest='edl',
        action='store_true',
    )
    parser.add_argument('-r', '--re-encode', help='Re-encode video', dest='reEncode', action='store_true')
    parser.add_argument(
        '-b', '--burn', help='Hard-coded subtitles (implies re-encode)', dest='hardCode', action='store_true'
    )
    parser.add_argument(
        '-v',
        '--video-params',
        help='Video parameters for ffmpeg (only if re-encoding)',
        dest='vParams',
        default=VIDEO_DEFAULT_PARAMS,
    )
    parser.add_argument(
        '-a', '--audio-params', help='Audio parameters for ffmpeg', dest='aParams', default=AUDIO_DEFAULT_PARAMS
    )
    parser.set_defaults(
        embedSubs=False,
        fullSubs=False,
        subsOnly=False,
        offline=False,
        reEncode=False,
        hardCode=False,
        edl=False,
    )
    args = parser.parse_args()

    inFile = args.input
    outFile = args.output
    subsFile = args.subs
    lang = args.lang
    plexFile = args.plexAutoSkipJson
    if inFile:
        inFileParts = os.path.splitext(inFile)
        if not outFile:
            outFile = inFileParts[0] + "_clean" + inFileParts[1]
        if not subsFile:
            subsFile = GetSubtitles(inFile, lang, args.offline)
        if args.plexAutoSkipId and not plexFile:
            plexFile = inFileParts[0] + "_PlexAutoSkip_clean.json"

    if plexFile and not args.plexAutoSkipId:
        raise ValueError(
            f'Content ID must be specified if creating a PlexAutoSkip JSON file (https://github.com/mdhiggins/PlexAutoSkip/wiki/Identifiers)'
        )

    cleaner = VidCleaner(
        inFile,
        subsFile,
        outFile,
        args.subsOut,
        args.swears,
        args.pad,
        args.embedSubs,
        args.fullSubs,
        args.subsOnly,
        args.edl,
        lang,
        args.reEncode,
        args.hardCode,
        args.vParams,
        args.aParams,
        plexFile,
        args.plexAutoSkipId,
    )
    cleaner.CreateCleanSubAndMuteList()
    cleaner.MultiplexCleanVideo()


#################################################################################
if __name__ == '__main__':
    RunCleanvid()

#################################################################################
