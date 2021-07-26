#!/usr/bin/env python3

import argparse
import chardet
import codecs
import errno
import os
import shutil
import sys
import re
import pysrt
import delegator
from subliminal import *
from babelfish import Language
from caselessdictionary import CaselessDictionary
from itertools import tee

__script_location__ = os.path.dirname(os.path.realpath(__file__))

# thanks https://docs.python.org/3/library/itertools.html#recipes
def pairwise(iterable):
  a, b = tee(iterable)
  next(b, None)
  return zip(a, b)

######## GetSubtitles #########################################################
def GetSubtitles(vidFileSpec, srtLanguage):
  subFileSpec = ""

  if os.path.isfile(vidFileSpec):
    subFileParts = os.path.splitext(vidFileSpec)
    subFileSpec = subFileParts[0] + "." + str(Language(srtLanguage)) + ".srt";
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
  tmpSubsFileSpec = ""
  outputVidFileSpec = ""
  swearsFileSpec = ""
  swearsPadMillisec = 0
  fullSubs = False
  swearsMap = CaselessDictionary({})
  muteTimeList = []

  ######## init #################################################################
  def __init__(self, iVidFileSpec, iSubsFileSpec, oVidFileSpec, oSubsFileSpec, iSwearsFileSpec, swearsPadSec=0, fullSubs=False):

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
    self.fullSubs = fullSubs

  ######## del ##################################################################
  def __del__(self):
    if os.path.isfile(self.cleanSubsFileSpec) and (not os.path.isfile(self.outputVidFileSpec)):
      os.remove(self.cleanSubsFileSpec)
    if os.path.isfile(self.tmpSubsFileSpec):
      os.remove(self.tmpSubsFileSpec)

  ######## CreateCleanSubAndMuteList #################################################
  def CreateCleanSubAndMuteList(self):
    subFileParts = os.path.splitext(self.inputSubsFileSpec)

    self.tmpSubsFileSpec = subFileParts[0] + "_utf8" + subFileParts[1]
    shutil.copy2(self.inputSubsFileSpec, self.tmpSubsFileSpec)
    UTF8Convert(self.tmpSubsFileSpec)

    if not self.cleanSubsFileSpec:
      self.cleanSubsFileSpec = subFileParts[0] + "_clean" + subFileParts[1]

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
      newTextPeek = replacer.sub(lambda x: self.swearsMap[x.group()], subPeek.text) if (subPeek is not None) else None
           # this sub contains profanity, or
      if ((newText != sub.text) or
            # we have defined a pad, and
          ((self.swearsPadMillisec > 0) and (newTextPeek is not None) and
             # the next sub contains profanity and is within pad seconds of this one, or
           (((newTextPeek != subPeek.text) and ((subPeek.start.ordinal - sub.end.ordinal) <= self.swearsPadMillisec)) or
             # the previous sub contained profanity and is within pad seconds of this one
            ((prevNaughtySub is not None) and ((sub.start.ordinal - prevNaughtySub.end.ordinal) <= self.swearsPadMillisec))))):
        subScrubbed = (newText != sub.text)
        newSub = sub
        newSub.text = newText
        newSubs.append(newSub)
        if subScrubbed:
          prevNaughtySub = sub
          newTimes = [pysrt.SubRipTime.from_ordinal(sub.start.ordinal - self.swearsPadMillisec).to_time(),
                      pysrt.SubRipTime.from_ordinal(sub.end.ordinal + self.swearsPadMillisec).to_time()]
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
    for timePair in newTimestampPairs:
      lineStart = (timePair[0].hour * 60.0 * 60.0) + (timePair[0].minute * 60.0) + timePair[0].second + (timePair[0].microsecond / 1000000.0)
      lineEnd = (timePair[1].hour * 60.0 * 60.0) + (timePair[1].minute * 60.0) + timePair[1].second + (timePair[1].microsecond / 1000000.0)
      self.muteTimeList.append("volume=enable='between(t," + format(lineStart, '.3f') + "," + format(lineEnd, '.3f') + ")':volume=0")

  ######## MultiplexCleanVideo ###################################################
  def MultiplexCleanVideo(self):
    if len(self.muteTimeList) > 0:
      ffmpegCmd = "ffmpeg -y -i \"" + self.inputVidFileSpec + "\"" + \
                      " -c:v copy " + \
                      " -af \"" + ",".join(self.muteTimeList) + "\"" \
                      " -c:a aac -ac 2 -ab 224k -ar 44100 \"" + \
                      self.outputVidFileSpec + "\""
      ffmpegResult = delegator.run(ffmpegCmd, block=True)
      if (ffmpegResult.return_code != 0) or (not os.path.isfile(self.outputVidFileSpec)):
        print(ffmpegCmd)
        print(ffmpegResult.err)
        raise ValueError(f'Could not process {self.inputVidFileSpec}')
    else:
      shutil.copy2(self.inputVidFileSpec, self.outputVidFileSpec)

#################################################################################


#################################################################################
if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument('-s', '--subs',   help='.srt subtitle file (will attempt auto-download if unspecified)', metavar='<srt>')
  parser.add_argument('-i', '--input',  help='input video file', metavar='<input video>')
  parser.add_argument('-o', '--output', help='output video file', metavar='<output video>')
  parser.add_argument(      '--subs-output', help='output subtitle file', metavar='<output srt>', dest="subsOut")
  parser.add_argument('-w', '--swears', help='text file containing profanity (with optional mapping)', \
                                        default=os.path.join(__script_location__, 'swears.txt'), \
                                        metavar='<profanity file>')
  parser.add_argument('-l', '--lang',   help='language for srt download (default is "eng")', default='eng', metavar='<language>')
  parser.add_argument('-p', '--pad',    help='pad (seconds) around profanity', metavar='<int>', dest="pad", type=int, default=0)
  parser.add_argument('--full-subs',    help='include all subtitles in output subtitle file (not just scrubbed)', dest='fullSubs', action='store_true')
  parser.set_defaults(fullSubs=False)
  args = parser.parse_args()

  inFile = args.input
  outFile = args.output
  subsFile = args.subs
  lang = args.lang
  if inFile:
    inFileParts = os.path.splitext(inFile)
    if (not outFile):
      outFile = inFileParts[0] + "_clean" + inFileParts[1]
    if (not subsFile):
      subsFile = GetSubtitles(inFile, lang)

  cleaner = VidCleaner(inFile, subsFile, outFile, args.subsOut, args.swears, args.pad, args.fullSubs)
  cleaner.CreateCleanSubAndMuteList()
  cleaner.MultiplexCleanVideo()

#################################################################################
