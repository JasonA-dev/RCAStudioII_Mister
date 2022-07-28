/*
void Pixie::cyclePixie()
{
    int j;
	Byte v, vram1, vram2;
	int color;

	if (graphicsNext_ == 0)
	{
        p_Computer->debugTrace("----  H.Sync");
		graphicsMode_++;
		if (graphicsMode_ == 60) pixieEf_ = 0;
		if (graphicsMode_ == 64) pixieEf_ = 1;
		if (graphicsMode_ == 188) pixieEf_ = 0;
		if (graphicsMode_ == 192) pixieEf_ = 1;

		if (graphicsMode_ >= 262)
		{
			if (changeScreenSize_)
			{
				changeScreenSize();
				if (!fullScreenSet_)
					p_Main->pixieBarSizeEvent();
				changeScreenSize_ = false;
			}
			graphicsMode_ = 0;
			copyScreen();
			videoSyncCount_++;
		}

	}

	if (graphicsNext_ == 2)
	{
		if (graphicsMode_ == 62)
		{
			if (graphicsOn_)
			{
				p_Computer->pixieInterrupt();
				vidInt_ = 1;
				p_Computer->setCycle0();
			}
			else vidInt_ = 0;
		}
	}

	if (graphicsMode_ >= 64 && graphicsMode_ <=191 && graphicsOn_ && vidInt_ == 1 && graphicsNext_ >=4 && graphicsNext_ < (4+graphicsX_))
	{
		j = 0;
		while(graphicsNext_ >= 4 && graphicsNext_ < (4+graphicsX_))
		{
			graphicsNext_ ++;
			{
				v = p_Computer->pixieDmaOut(&color);
				for (int i=0; i<8; i++)
				{
					plot(j+i, (int)graphicsMode_-64,(v & 128) ? 1 : 0, (color|colourMask_)&7);
					if (graphicsX_ == 16)
						plot(j+i, (int)graphicsMode_-63,(v & 128) ? 1 : 0, (color|colourMask_)&7);
					v <<= 1;
				}
			}
			j += 8;
		}
		if (graphicsX_ == 16)
			graphicsMode_++;
		p_Computer->setCycle0();
		graphicsNext_ -= 1;
	}

	graphicsNext_ += 1;
	if (graphicsNext_ > (5+graphicsX_))
		graphicsNext_ = 0;
}
*/