//
//  AV7zAppResourceLoader.m
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//

#import "AV7zAppResourceLoader.h"

#import "LZMAExtractor.h"

@implementation AV7zAppResourceLoader

@synthesize archiveFilename = m_archiveFilename;

- (void) dealloc
{
  self.archiveFilename = nil;
  [super dealloc];
}

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader
{
  return [[[AV7zAppResourceLoader alloc] init] autorelease];
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 4, @"arr count");
  
  // Pass ARCHIVE_PATH ARCHIVE_ENTRY_NAME TMP_PATH
  
  NSString *archivePath = [arr objectAtIndex:0];
  NSString *archiveEntry = [arr objectAtIndex:1];
  NSString *phonyOutPath = [arr objectAtIndex:2];
  NSString *outPath = [arr objectAtIndex:3];
    
  BOOL worked;
  worked = [LZMAExtractor extractArchiveEntry:archivePath archiveEntry:archiveEntry outPath:phonyOutPath];
  assert(worked);
  
  // Move phony tmp filename to the expected filename once writes are complete
  
  worked = [[NSFileManager defaultManager] moveItemAtPath:phonyOutPath toPath:outPath error:nil];
  NSAssert(worked, @"moveItemAtPath failed for decode result");
  
  [pool drain];
}

- (void) _detachNewThread:(NSString*)archivePath
            archiveEntry:(NSString*)archiveEntry
            phonyOutPath:(NSString*)phonyOutPath
                 outPath:(NSString*)outPath
{
  NSArray *arr = [NSArray arrayWithObjects:archivePath, archiveEntry, phonyOutPath, outPath, nil];
  NSAssert([arr count] == 4, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];  
}

- (void) load
{
  // Avoid kicking off mutliple sync load operations. This method should only
  // be invoked from a main thread callback, so there should not be any chance
  // of a race condition involving multiple invocations of this load mehtod.
  
  if (startedLoading) {
    return;
  } else {
    self->startedLoading = TRUE;    
  }

  // Superclass load method asserts that self.movieFilename is not nil
  [super load];

  if (self.archiveFilename == nil) {
    // If no archive filename is indicated, but an entry filename is, then assume
    // the archive name. For example, if movieFilename is "2x2_black_blue_16BPP.mov"
    // then assume an archive filename of "2x2_black_blue_16BPP.mov.7z"
    self.archiveFilename = [NSString stringWithFormat:@"%@.7z", self.movieFilename];
  }
    
  NSString *archiveFilename = self.archiveFilename;
  NSString *archivePath = [self _getResourcePath:archiveFilename];
  NSString *archiveEntry = self.movieFilename;
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *outPath = [tmpDir stringByAppendingPathComponent:archiveEntry];
  
  // Generate a phony /tmp filename, data is written to the phony path name and then
  // the result is renamed to outPath once complete. This avoids thread race conditions
  // and partial writes. Note that the filename is generated in this method, and this
  // method should only be invoked from the main thread.  

  NSDate *nowDate = [NSDate date];
  NSTimeInterval ti = [nowDate timeIntervalSince1970];
  uint64_t ival = (uint64_t)(ti * 1000.0);
  NSString *phonyOutFilename = [NSString stringWithFormat:@"%qi", ival];
  NSString *phonyOutPath = [tmpDir stringByAppendingPathComponent:phonyOutFilename];

  [self _detachNewThread:archivePath archiveEntry:archiveEntry phonyOutPath:phonyOutPath outPath:outPath];
  
  return;
}

// Given a filename (typically an archive entry name), return the filename
// in the tmp dir that corresponds to the entry. For example,
// "2x2_black_blue_16BPP.mov" -> "/tmp/2x2_black_blue_16BPP.mov" where "/tmp"
// is the app tmp dir.

- (NSString*) _getTmpDirPath:(NSString*)filename
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSAssert(tmpDir, @"tmpDir");
  NSString *outPath = [tmpDir stringByAppendingPathComponent:filename];
  NSAssert(outPath, @"outPath");
  return outPath;
}

// Define isMovieReady so that TRUE is returned if the mov file
// has been decompressed already.

- (BOOL) isMovieReady
{
  BOOL isMovieReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  
  // Return TRUE if the decoded mov file exists in the tmp dir
  
  NSString *tmpMoviePath = [self _getTmpDirPath:self.movieFilename];
  
  if ([self _fileExists:tmpMoviePath]) {
    isMovieReady = TRUE;
  }
  
  return isMovieReady;
}

@end
